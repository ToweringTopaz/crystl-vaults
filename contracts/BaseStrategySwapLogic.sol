// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./libs/FullMath.sol";
import "./libs/LibVaultSwaps.sol";

import "./BaseStrategy.sol";

//Contains the strategy's functions related to swapping, earning, etc.
abstract contract BaseStrategySwapLogic is BaseStrategy {
    using SafeERC20 for IERC20;
    using LibVaultConfig for VaultFees;
    
    //max number of supported lp/earned tokens
    uint256 constant LP_LEN = 2;
    uint256 constant EARNED_LEN = 8;
    
    //Token constants used for fees, etc
    address constant DAI = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address constant CRYSTL = 0x76bF0C28e604CC3fE9967c83b3C3F31c213cfE64;

    uint256 constant WITHDRAW_FEE_FACTOR_MAX = 10000; //means 0% withdraw fee minimum

    address immutable public wantAddress; //The token which is deposited and earns a yield 
    uint256 immutable earnedLength; //number of earned tokens;
    uint256 immutable lpTokenLength; //number of underlying tokens (for a LP strategy, usually 2);
    
    address[EARNED_LEN] public earned;
    address[LP_LEN] public lpToken;
    
    VaultFees public vaultFees;
    LibVaultSwaps.VaultStats public vaultStats;

    event SetFees(VaultFees _fees);

    constructor(
        address _wantAddress,
        address[] memory _earned
    ) {
        wantAddress = _wantAddress;
        
        uint i;
        //The number of earned tokens should not be expected to change
        for (i = 0; i < _earned.length && _earned[i] != address(0); i++) {
            earned[i] = _earned[i];
        }
        earnedLength = i;
        
        //Look for LP tokens. If not, want must be a single-stake
        uint _lpTokenLength;
        try IUniPair(_wantAddress).token0() returns (address _token0) {
            lpToken[0] = _token0;
            lpToken[1] = IUniPair(_wantAddress).token1();
            _lpTokenLength = 2;
        } catch { //if not LP, then single stake
            lpToken[0] = _wantAddress;
            _lpTokenLength = 1;
        }
        lpTokenLength = _lpTokenLength;
    }
    
    function buyBackRate() external view returns (uint) { 
        return vaultFees.burn.rate;
    }
    function burnedAmount() external view returns (uint) {
        return vaultStats.totalBurned;
    }
    
    function _wantBalance() internal override view returns (uint256) {
        return IERC20(wantAddress).balanceOf(address(this));
    }
    //transfers the want token
    function _transferWant(address _to, uint256 _amount) internal {
        IERC20(wantAddress).safeTransfer(_to, _amount);   
    }
    //approves the want token for transfer out
    function _approveWant(address _to, uint256 _amount) override internal {
        IERC20(wantAddress).safeIncreaseAllowance(_to, _amount);   
    }
    
    function setFees(VaultFees calldata _fees) external virtual onlyGov {
        _fees.check();
        vaultFees = _fees;
        emit SetFees(_fees);
    }

    function _earn(address _to) internal virtual whenEarnIsReady {
        
        uint wantBalanceBefore = _wantBalance(); //Don't touch starting want balance (anti-rug)
        
        _vaultHarvest(); // Harvest farm tokens

        uint dust = settings.dust; //minimum number of tokens to bother trying to compound
        bool success;
        
        for (uint i; i < earnedLength; i++) { //Process each earned token, whether it's 1, 2, or 8. 
            address earnedAddress = earned[i];
            uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));
            if (earnedAddress == wantAddress)
                earnedAmt -= wantBalanceBefore; //ignore pre-existing want tokens
                
            if (earnedAmt > dust) {
                success = true; //We have something worth compounding
                earnedAmt = LibVaultSwaps.distributeFees(settings, vaultFees, vaultStats, earnedAddress, earnedAmt, _to); // handles all fees for this earned token
                // Swap half earned to token0, half to token1 (or split evenly however we must, for balancer etc)
                // Same logic works if lpTokenLength == 1 ie single-staking pools
                for (uint j; j < lpTokenLength; j++) {
                    _safeSwap(earnedAmt / lpTokenLength, earnedAddress, lpToken[j], address(this));
                }
            }
        }
        //lpTokenLength == 1 means single-stake, not LP
        if (success) {
            if (lpTokenLength > 1) {
                // Get want tokens, ie. add liquidity
                LibVaultSwaps.optimalMint(wantAddress, lpToken[0], lpToken[1]);
            }
            _farm();
        }
        lastEarnBlock = block.number;
    }
    
    function _safeSwap(
        uint256 _amountIn,
        address _tokenA,
        address _tokenB,
        address _to
    ) internal {
        LibVaultSwaps._safeSwap(settings, _amountIn, _tokenA, _tokenB, _to);
    }
    
    function collectWithdrawFee(uint _wantAmt) internal returns (uint) {
        uint256 withdrawFee = FullMath.mulDiv(
            _wantAmt,
            WITHDRAW_FEE_FACTOR_MAX - vaultFees.withdraw.rate,
            WITHDRAW_FEE_FACTOR_MAX
        );
        
        //if receiver is 0, strategy keeps fee
        address receiver = vaultFees.withdraw.receiver;
        if (receiver != address(0))
            _transferWant(receiver, withdrawFee);
        return _wantAmt - withdrawFee;
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