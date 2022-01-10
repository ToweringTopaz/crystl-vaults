// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./PrismLibrary.sol";
import "./Vault.sol";
import "hardhat/console.sol";
import {SafeERC20Upgradeable as SafeERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {AddressUpgradeable as Address} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

//Functions specific to the strategy code
library LibVaultSwaps {
    using SafeERC20 for IERC20;
    using Address for address;
    
    uint256 constant FEE_MAX = 10000; // 100 = 1% : basis points
    
    struct SwapConfig {

        IMagnetite magnetite;
        IUniRouter router;
        uint16 slippageFactor;
        bool feeOnTransfer;
    }

    function distribute(uint256 feeRate, SwapConfig memory swap, IERC20 _earnedToken, uint256 _earnedAmt) internal returns (uint earnedAmt) {
        if (feeRate > 0) {
            assert(feeRate <= FEE_MAX);
            uint fee = feeRate * _earnedAmt / FEE_MAX;
            safeSwap(swap, fee, _earnedToken, swap.router.WETH(), msg.sender); //msg.sender is vaulthealer
            _earnedAmt -= fee;
        }
        return _earnedAmt;
    }

    function safeSwap(
        SwapConfig memory swap,
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
        IERC20[] memory path = swap.magnetite.findAndSavePath(address(swap.router), _tokenA, _tokenB);
        
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

        uint256[] memory amounts = swap.router.getAmountsOut(_amountIn, cleanedUpPath);
        uint256 amountOut = amounts[amounts.length - 1] * swap.slippageFactor / 10000;
        
        //allow swap.router to pull the correct amount in
        IERC20(_tokenA).safeIncreaseAllowance(address(swap.router), _amountIn);
        
        if (_tokenB != swap.router.WETH() ) {
            if (swap.feeOnTransfer) { //reflect mode on
                swap.router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    _amountIn, amountOut, cleanedUpPath, _to, block.timestamp);
            } else { //reflect mode off
                swap.router.swapExactTokensForTokens(
                    _amountIn,amountOut, cleanedUpPath, _to, block.timestamp);
            }
        } else {
            if (swap.feeOnTransfer) { //reflect mode on
                swap.router.swapExactTokensForETHSupportingFeeOnTransferTokens(
                    _amountIn, amountOut, cleanedUpPath, _to, block.timestamp);
            } else { //reflect mode off
                swap.router.swapExactTokensForETH(
                    _amountIn ,amountOut, cleanedUpPath, _to, block.timestamp);
            }            
        }

    }
    
}