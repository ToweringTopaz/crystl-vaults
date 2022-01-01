 // SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./libs/HardMath.sol";
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
    uint256 constant EARNED_LEN = 4;

    IERC20 immutable public wantToken; //The token which is deposited and earns a yield 

    IERC20[EARNED_LEN] public earned;
    IERC20[LP_LEN] public lpToken;

    constructor(
        IERC20 _wantToken,
        IERC20[] memory _earned,
        address _targetVault
    ) {
        wantToken = _wantToken;

        for (uint i; i < _earned.length && address(_earned[i]) != address(0); i++) {
            earned[i] = _earned[i];
        }
        
        //Look for LP tokens. If not, want must be a single-stake
        try IUniPair(address(_wantToken)).token0() returns (address _token0) {
            lpToken[0] = IERC20(_token0);
            lpToken[1] = IERC20(IUniPair(address(_wantToken)).token1());
        } catch { //if not LP, then single stake
            lpToken[0] = _wantToken;
        }

    }

    function _wantBalance() internal override view returns (uint256) {
        return wantToken.balanceOf(address(this));
    }

    function _earn() internal virtual returns (bool success) {
        uint wantBalanceBefore = _wantBalance(); //Don't touch starting want balance (anti-rug)
        uint wantLockedBefore = wantBalanceBefore + vaultSharesTotal();
        _vaultHarvest(); // Harvest farm tokens

        uint dust = settings.dust; //minimum number of tokens to bother trying to compound

        LibVaultSwaps.SwapConfig memory swap = LibVaultSwaps.SwapConfig({
            magnetite: settings.magnetite,
            router: settings.router,
            slippageFactor: settings.slippageFactor,
            feeOnTransfer: settings.feeOnTransfer
        });
        
        for (uint i; address(earned[i]) != address(0); i++) { //Process each earned token, whether it's 1, 2, or 8. 
            IERC20 earnedToken = earned[i];
            uint256 earnedAmt = earnedToken.balanceOf(address(this));
            if (earnedToken == wantToken)
                earnedAmt -= wantBalanceBefore; //ignore pre-existing want tokens
                
            if (earnedAmt > dust) {
                success = true; //We have something worth compounding

                LibVaultSwaps.safeSwap(swap, earnedAmt, earnedToken, IERC20(swap.router.WETH()), address(vaultHealer));

            }
        }
    }

    //The proceeds from depositAmt are treated much the same as direct want token deposits. The remainder represents autocompounded earnings 
    //which don't generate new shares of any kind
    function compound(uint256 depositAmt, uint256 exportSharesTotal, uint256 _sharesTotal) external payable onlyVaultHealer returns (uint256 sharesAdded) {
        assert(msg.value >= depositAmt);
        uint wantLockedBefore = wantLockedTotal();

        LibVaultSwaps.SwapConfig memory swap = LibVaultSwaps.SwapConfig({
            magnetite: settings.magnetite,
            router: settings.router,
            slippageFactor: settings.slippageFactor,
            feeOnTransfer: settings.feeOnTransfer
        });

        if (address(lpToken[1]) == address(0)) { //single stake
            LibVaultSwaps.safeSwapFromETH(swap, msg.value, lpToken[0], address(this));
        } else {
            LibVaultSwaps.safeSwapFromETH(swap, msg.value / 2, lpToken[0], address(this));
            LibVaultSwaps.safeSwapFromETH(swap, msg.value / 2, lpToken[1], address(this));
            LibVaultSwaps.optimalMint(wantToken, lpToken[0], lpToken[1]); // Get want tokens, ie. add liquidity
        }
        _farm();

        uint wantAdded = wantLockedTotal() - wantLockedBefore;

        sharesAdded = wantAdded * depositAmt / msg.value; //portion to be counted as a deposit, minting shares
        if (_sharesTotal > 0) {
            sharesAdded = HardMath.mulDiv(sharesAdded, _sharesTotal, (wantLockedBefore - exportSharesTotal));
        }

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

   receive() external payable {
        assert(msg.sender == address(settings.router)); // only accept ETH via fallback if it's a router refund
    }
}