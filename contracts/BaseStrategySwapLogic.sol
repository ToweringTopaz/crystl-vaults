 // SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./libs/HardMath.sol";
import "./libs/LibQuartz.sol";
import "./BaseStrategy.sol";
import "./libs/Vault.sol";
import "./libs/PrismLibrary.sol";
import {SafeERC20Upgradeable as SafeERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {AddressUpgradeable as Address} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "./libs/IVaultHealer.sol";

//Contains the strategy's functions related to swapping, earning, etc.
abstract contract BaseStrategySwapLogic is BaseStrategy {
    using SafeERC20 for IERC20;

    uint constant FEE_MAX = 10000;

    function isMaximizer() public view returns (bool) {
        return address(targetVault) != address(0);
    }

    function _wantBalance() internal override view returns (uint256) {
        return wantToken.balanceOf(address(this));
    }

    function earn(Vault.Fees calldata earnFees) external returns (bool success, uint256 _wantLockedTotal) {
        uint wantBalanceBefore = _wantBalance(); //Don't sell starting want balance (anti-rug)

        _vaultHarvest(); // Harvest farm tokens

        uint dust = settings.dust; //minimum number of tokens to bother trying to compound
        
        success;
        for (uint i; address(earned[i]) != address(0); i++) { //Process each earned token, whether it's 1, 2, or 8. 
            IERC20 earnedToken = earned[i];
            uint256 earnedAmt = earnedToken.balanceOf(address(this));
            if (earnedToken == wantToken)
                earnedAmt -= wantBalanceBefore; //ignore pre-existing want tokens
                
            if (earnedAmt > dust) {
                success = true; //We have something worth compounding
                earnedAmt = distribute(earnFees, earnedToken, earnedAmt); // handles all fees for this earned token

                if (address(lpToken[1]) == address(0)) { //single stake
                    safeSwap(earnedAmt, earnedToken, lpToken[0], address(this));
                } else {
                    safeSwap(earnedAmt / 2, earnedToken, lpToken[0], address(this));
                    safeSwap(earnedAmt / 2, earnedToken, lpToken[1], address(this));
                }
            }
        }
        //lpTokenLength == 1 means single-stake, not LP
        if (success) {

            if (isMaximizer()) {
                IERC20 crystlToken = maximizerRewardToken; //todo: change this from a hardcoding
                uint256 crystlBalance = crystlToken.balanceOf(address(this));

                IVaultHealer(msg.sender).deposit(targetVid, crystlBalance);
            } else {
                if (address(lpToken[1]) != address(0)) {
                    // Get want tokens, ie. add liquidity
                    LibQuartz.optimalMint(IUniPair(address(wantToken)), lpToken[0], lpToken[1]);
                }
                _farm();
            }
        }
        _wantLockedTotal = wantLockedTotal();
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

    function distribute(Vault.Fees calldata earnFees, IERC20 _earnedToken, uint256 _earnedAmt) internal returns (uint earnedAmt) {

        earnedAmt = _earnedAmt;
        IUniRouter router = settings.router;
        // To pay for earn function
        uint256 fee = _earnedAmt * earnFees.userReward.rate / FEE_MAX;
        if (fee > 0) {
            safeSwap(fee, _earnedToken, router.WETH(), tx.origin);
            earnedAmt -= fee;
            }

        //distribute rewards
        fee = _earnedAmt * earnFees.treasuryFee.rate / FEE_MAX;
        if (fee > 0) {
            safeSwap(fee, _earnedToken, router.WETH(), earnFees.treasuryFee.receiver);
            earnedAmt -= fee;
            }
        
        //burn crystl
        fee = _earnedAmt * earnFees.burn.rate / FEE_MAX;
        if (fee > 0) {
            safeSwap(fee, _earnedToken, router.WETH(), earnFees.burn.receiver);
            earnedAmt -= fee;
            }
    }

    function safeSwap(
        uint256 _amountIn,
        IERC20 _tokenA,
        IERC20 _tokenB,
        address _to
    ) internal {
        
        //Handle one-token paths which are simply a transfer
        if (_tokenA == _tokenB) {
            if (_to != address(this)) //skip transfers to self
                _tokenA.safeTransfer(_to, _amountIn);
            return;
        }
        IUniRouter router = settings.router;  
        IERC20[] memory path = settings.magnetite.findAndSavePath(address(router), _tokenA, _tokenB);      
        /////////////////////////////////////////////////////////////////////////////////////////////
        //this code snippet below could be removed if findAndSavePath returned a right-sized array //
        uint256 counter=0;
        for (counter; counter<path.length; counter++){
            if (address(path[counter]) == address(0)) break;
        }
        IERC20[] memory cleanedUpPath = new IERC20[](counter);
        for (uint256 i=0; i<counter; i++) {
            cleanedUpPath[i] =path[i];
        }
        //this code snippet above could be removed if findAndSavePath returned a right-sized array


        uint256[] memory amounts = router.getAmountsOut(_amountIn, cleanedUpPath);
        uint256 amountOut = amounts[amounts.length - 1] * settings.slippageFactor / 10000;
        
        //allow swap.router to pull the correct amount in
        IERC20(_tokenA).safeIncreaseAllowance(address(settings.router), _amountIn);
        bool feeOnTransfer = settings.feeOnTransfer;

        if (_tokenB != router.WETH() || Address.isContract(_to) ) {
            if (feeOnTransfer) { //reflect mode on
                router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    _amountIn, amountOut, cleanedUpPath, _to, block.timestamp);
            } else { //reflect mode off
                router.swapExactTokensForTokens(
                    _amountIn, amountOut, cleanedUpPath, _to, block.timestamp);
            }
        } else { //Non-contract address (extcodesize zero) receives native ETH
            if (feeOnTransfer) { //reflect mode on
                router.swapExactTokensForETHSupportingFeeOnTransferTokens(
                    _amountIn, amountOut, cleanedUpPath, _to, block.timestamp);
            } else { //reflect mode off
                router.swapExactTokensForETH(
                    _amountIn ,amountOut, cleanedUpPath, _to, block.timestamp);
            }            
        }
    }
}