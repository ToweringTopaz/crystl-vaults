// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./PrismLibrary.sol";
import "./VaultSettings.sol";
import "hardhat/console.sol";
import "./IWETH.sol";

//Functions specific to the strategy code
library LibVaultSwaps {
    using SafeERC20 for IERC20;
    using Address for address;
    
    uint16 constant FEE_MAX = 10000; // 100 = 1% : basis points

    function safeSwap(
        VaultSettings calldata settings,
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
        address[] memory path = settings.magnetite.findAndSavePath(settings.router, address(_tokenA), address(_tokenB));
        
        /////////////////////////////////////////////////////////////////////////////////////////////
        //this code snippet below could be removed if findAndSavePath returned a right-sized array //
        uint256 counter=0;
        for (counter; counter<path.length; counter++){
            if (path[counter]==address(0)) break;
        }
        address[] memory cleanedUpPath = new address[](counter);
        for (uint256 i=0; i<counter; i++) {
            cleanedUpPath[i] =path[i];
        }
        //this code snippet above could be removed if findAndSavePath returned a right-sized array

        uint256[] memory amounts = settings.router.getAmountsOut(_amountIn, cleanedUpPath);
        uint256 amountOut = amounts[amounts.length - 1] * settings.slippageFactor / 10000;
        
        //allow settings.router to pull the correct amount in
        IERC20(_tokenA).safeIncreaseAllowance(address(settings.router), _amountIn);
        
        if (_tokenB == settings.router.WETH()) {
            if (settings.feeOnTransfer) { //reflect mode on
                settings.router.swapExactTokensForETHSupportingFeeOnTransferTokens(
                    _amountIn, amountOut, cleanedUpPath, _to, block.timestamp);
            } else { //reflect mode off
                settings.router.swapExactTokensForETH(
                    _amountIn ,amountOut, cleanedUpPath, _to, block.timestamp);
            } 
        } else {
            if (settings.feeOnTransfer) { //reflect mode on
                settings.router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    _amountIn, amountOut, cleanedUpPath, _to, block.timestamp);
            } else { //reflect mode off
                settings.router.swapExactTokensForTokens(
                    _amountIn,amountOut, cleanedUpPath, _to, block.timestamp);
            }
        }
    }

    function safeSwapToETH(
        VaultSettings calldata settings,
        uint256 _amountIn,
        IERC20 _tokenA,
        address _to
    ) internal {
        safeSwap(settings, _amountIn, _tokenA, settings.router.WETH(), _to);
    }

    function safeSwapFromETH(
        VaultSettings calldata settings,
        uint256 _amountIn,
        IERC20 _tokenB,
        address _to
    ) internal {
        
        IWETH _tokenA = settings.router.WETH();

        //Handle one-token paths by simply making ERC20 wnative
        if (_tokenA == _tokenB) {
            IWETH(_tokenA).deposit{value: _amountIn}();
            if (_to != address(this)) //skip transfers to self
                IERC20(_tokenA).safeTransfer(_to, _amountIn);
            return;
        }
        address[] memory path = settings.magnetite.findAndSavePath(settings.router, address(_tokenA), address(_tokenB));
        
        /////////////////////////////////////////////////////////////////////////////////////////////
        //this code snippet below could be removed if findAndSavePath returned a right-sized array //
        uint256 counter=0;
        for (counter; counter<path.length; counter++){
            if (path[counter]==address(0)) break;
        }
        address[] memory cleanedUpPath = new address[](counter);
        for (uint256 i=0; i<counter; i++) {
            cleanedUpPath[i] =path[i];
        }
        //this code snippet above could be removed if findAndSavePath returned a right-sized array

        uint256[] memory amounts = settings.router.getAmountsOut(_amountIn, cleanedUpPath);
        uint256 amountOut = amounts[amounts.length - 1] * settings.slippageFactor / 10000;
        
        if (settings.feeOnTransfer) { //reflect mode on
            settings.router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: _amountIn}(amountOut, cleanedUpPath, _to, block.timestamp);
        } else { //reflect mode off
            settings.router.swapExactETHForTokens{value: _amountIn}(amountOut, cleanedUpPath, _to, block.timestamp);
        } 
        
    }
    
    //based on liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);    
    function optimalMint(IUniPair pair, IERC20 tokenA, IERC20 tokenB) internal returns (uint liquidity) {
        (address token0, address token1) = PrismLibrary.sortTokens(address(tokenA), address(tokenB));

        (uint reserve0, uint reserve1,) = IUniPair(address(pair)).getReserves();
        if (reserve0 == 0 || reserve1 == 0) return 0; 

        uint totalSupply = pair.totalSupply();
        
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));

        uint liquidity0 = balance0 * totalSupply / reserve0;
        uint liquidity1 = balance1 * totalSupply / reserve1;

        if (liquidity0 < liquidity1) {
            balance1 = reserve1 * balance0 / reserve0;
        } else if (liquidity1 < liquidity0) {
            balance0 = reserve0 * balance1 / reserve1;
        }

        IERC20(token0).safeTransfer(address(pair), balance0);
        IERC20(token1).safeTransfer(address(pair), balance1);
        liquidity = IUniPair(address(pair)).mint(address(this));
    }
    
}