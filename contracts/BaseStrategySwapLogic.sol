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
    
    function isMaximizer() public view returns (bool) {
        return address(targetVault) != address(0);
    }

    function _wantBalance() internal override view returns (uint256) {
        return wantToken.balanceOf(address(this));
    }

    function _earn(VaultFees calldata earnFees) internal virtual returns (bool success) {
        uint wantBalanceBefore = _wantBalance(); //Don't touch starting want balance (anti-rug)
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
                earnedAmt = earnFees.distribute(swap, earnedToken, earnedAmt); // handles all fees for this earned token

                if (address(lpToken[1]) == address(0)) { //single stake
                    LibVaultSwaps.safeSwap(swap, earnedAmt, earnedToken, lpToken[0], address(this));
                } else {
                    LibVaultSwaps.safeSwap(swap, earnedAmt / 2, earnedToken, lpToken[0], address(this));
                    LibVaultSwaps.safeSwap(swap, earnedAmt / 2, earnedToken, lpToken[1], address(this));
                }
            }
        }
        //lpTokenLength == 1 means single-stake, not LP
        if (success) {

            if (isMaximizer()) {
                IERC20 crystlToken = maximizerRewardToken; //todo: change this from a hardcoding
                uint256 crystlBalance = crystlToken.balanceOf(address(this));

                //need to instantiate pool here?
                crystlToken.safeIncreaseAllowance(address(vaultHealer), crystlBalance);

                vaultHealer.stratDeposit(targetVid, crystlBalance);
            } else {
                if (address(lpToken[1]) != address(0)) {
                    // Get want tokens, ie. add liquidity
                    LibVaultSwaps.optimalMint(wantToken, lpToken[0], lpToken[1]);
                }
                _farm();
            }
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
}