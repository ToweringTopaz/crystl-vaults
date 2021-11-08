 // SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./libs/FullMath.sol";
import "./libs/LibVaultSwaps.sol";

import "./BaseStrategy.sol";
import "hardhat/console.sol";

//Contains the strategy's functions related to swapping, earning, etc.
abstract contract BaseStrategySwapLogic is BaseStrategy {
    using SafeERC20 for IERC20;
    using LibVaultConfig for VaultFees;
    using LibVaultSwaps for VaultFees;
    
    //max number of supported lp/earned tokens
    uint256 constant LP_LEN = 2;
    uint256 constant EARNED_LEN = 8;

    IERC20 immutable public wantToken; //The token which is deposited and earns a yield 
    uint256 immutable earnedLength; //number of earned tokens;
    uint256 immutable lpTokenLength; //number of underlying tokens (for a LP strategy, usually 2);
    
    IERC20[EARNED_LEN] public earned;
    IERC20[LP_LEN] public lpToken;
    
    VaultFees public vaultFees;
    LibVaultSwaps.VaultStats public vaultStats;

    event SetFees(VaultFees _fees);

    constructor(
        IERC20 _wantToken,
        IERC20[] memory _earned
    ) {
        wantToken = _wantToken;
        
        uint i;
        //The number of earned tokens should not be expected to change
        for (i = 0; i < _earned.length && address(_earned[i]) != address(0); i++) {
            earned[i] = _earned[i];
        }
        earnedLength = i;
        
        //Look for LP tokens. If not, want must be a single-stake
        uint _lpTokenLength;
        try IUniPair(address(_wantToken)).token0() returns (address _token0) {
            lpToken[0] = IERC20(_token0);
            lpToken[1] = IERC20(IUniPair(address(_wantToken)).token1());
            _lpTokenLength = 2;
        } catch { //if not LP, then single stake
            lpToken[0] = _wantToken;
            _lpTokenLength = 1;
        }
        lpTokenLength = _lpTokenLength;
    }
    
    modifier whenEarnIsReady { //returns without action if earn is not ready
        if (block.number >= lastEarnBlock + settings.minBlocksBetweenEarns && !paused()) {
            _;
        }
    }
    
    function buyBackRate() external view returns (uint) { 
        return vaultFees.burn.rate;
    }
    function burnedAmount() external view returns (uint) {
        return vaultStats.totalBurned;
    }
    
    function setFees(VaultFees calldata _fees) external virtual onlyGov {
        _fees.check();
        vaultFees = _fees;
        emit SetFees(_fees);
    }

    function _wantBalance() internal override view returns (uint256) {
        return wantToken.balanceOf(address(this));
    }

    function _earn(address _to) internal virtual whenEarnIsReady {
        
        uint wantBalanceBefore = _wantBalance(); //Don't touch starting want balance (anti-rug)
        console.log("just before harvest");
        _vaultHarvest(); // Harvest farm tokens

        uint dust = settings.dust; //minimum number of tokens to bother trying to compound
        bool success;
        
        for (uint i; i < earnedLength; i++) { //Process each earned token, whether it's 1, 2, or 8. 
            console.log("made it into the for loop");
            IERC20 earnedToken = earned[i];
            uint256 earnedAmt = earnedToken.balanceOf(address(this));
            if (earnedToken == wantToken)
                earnedAmt -= wantBalanceBefore; //ignore pre-existing want tokens
                
            if (earnedAmt > dust) {
                console.log("just past the dust conditional");

                success = true; //We have something worth compounding
                console.log(settings.dust);
                console.log(vaultStats.totalEarned);
                console.log(earnedAmt);
                console.log(_to);

                earnedAmt = vaultFees.distribute(settings, vaultStats, earnedToken, earnedAmt, _to); // handles all fees for this earned token
                // Swap half earned to token0, half to token1 (or split evenly however we must, for balancer etc)
                // Same logic works if lpTokenLength == 1 ie single-staking pools
                console.log("hello");
                for (uint j; j < lpTokenLength; j++) {
                    console.log("about to make the swap");
                    LibVaultSwaps.safeSwap(settings, earnedAmt / lpTokenLength, earnedToken, lpToken[j], address(this));
                }
            }
        }
        //lpTokenLength == 1 means single-stake, not LP
        if (success) {
            if (lpTokenLength > 1) {
                // Get want tokens, ie. add liquidity
                LibVaultSwaps.optimalMint(wantToken, lpToken[0], lpToken[1]);
            }
            console.log("just before _farm");
            _farm();
        }
        lastEarnBlock = block.number;
    }
    
    //Safely deposits want tokens in farm
    function _farm() override internal {
        uint256 wantAmt = _wantBalance();
        if (wantAmt == 0) return;
        
        uint256 sharesBefore = vaultSharesTotal();
        
        _vaultDeposit(wantAmt); //approves the transfer then calls the pool contract to deposit
        uint256 sharesAfter = vaultSharesTotal();
        
        //including settings.dust to reduce the chance of false positives
        //safety check, will fail if there's a deposit fee rugpull or serious bug taking deposits
        require(sharesAfter + _wantBalance() + settings.dust >= (sharesBefore + wantAmt) * settings.slippageFactor / 10000,
            "High vault deposit slippage");
        return;
    }
}