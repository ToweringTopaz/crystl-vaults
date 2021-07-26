// SPDX-License-Identifier: GPL

pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v2-core@1.0.1/contracts/interfaces/IUniswapV2Pair.sol";
import "./GibbonLibrary.sol";

library GibbonRouter {
    using SafeERC20 for IERC20;
    using GibbonLibrary for AmmData;
    using GibbonLibrary for AmmData[];
    
    // for simple one-step swaps
    function swap(
        AmmData _amm,
        uint amountIn,
        address tokenIn,
        address tokenOut,
        address recipient
    ) internal returns (uint amountOut) {
            
            //handle degenerate cases
            if (amountIn == 0) return 0;
            if (tokenIn == tokenOut) {
                if (recipient != address(this))
                    IERC20(tokenOut).safeTransfer(recipient, amountIn);
                return amountIn;
            }
            
            //calculate swap
            (uint reserveIn, uint reserveOut) = _amm.getReserves(tokenIn, tokenOut);
            amountOut = _amm.getAmountOut(amountIn, reserveIn, reserveOut);
            address pair = _amm.pairFor(tokenIn, tokenOut);
            
            //do the swap
            IERC20(tokenIn).safeTransfer(pair, amountIn);
            (uint amount0Out, uint amount1Out) = tokenIn < tokenOut ? (uint(0), amountOut) : (amountOut, uint(0));
            IUniswapV2Pair(pair).swap(amount0Out, amount1Out, recipient, new bytes(0));
            
    }
    
    function swap(
        AmmData _amm,
        uint amountIn,
        address[] memory path,
        address recipient
    ) internal returns (uint amountOut) {
        
        if (amountIn == 0) return 0;
        //the common case of the desired token being the token we already have
        if (path.length == 1) {
            if (recipient != address(this))
                IERC20(path[0]).safeTransfer(recipient, amountIn);
            return amountIn;
        }
        
        uint[] memory amounts = _amm.getAmountsOut(amountIn, path);
        amountOut = amounts[amounts.length - 1];
        
        IERC20(path[0]).safeTransfer(_amm.pairFor(path[0], path[1]), amounts[0]);
            
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (uint amount0Out, uint amount1Out) = input < output ? (uint(0), amounts[i + 1]) : (amounts[i + 1], uint(0));
            address to = i < path.length - 2 ? _amm.pairFor(output, path[i + 2]) : recipient;
            IUniswapV2Pair(_amm.pairFor(input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }
    
    //supporting multiple AMMs, with one preselected for each step
    function swap(
        AmmData[] memory _amms,
        uint amountIn,
        address[] memory path,
        address recipient
    ) internal returns (uint amountOut) {
        
        if (amountIn == 0) return 0;
        //the common case of the desired token being the token we already have
        if (path.length == 1) {
            IERC20(path[0]).safeTransfer(recipient, amountIn);
            return amountIn;
        }
        
        uint[] memory amounts = _amms.getAmountsOut(amountIn, path);
        amountOut = amounts[_amms.length]; // _amms.length == paths.length - 1
        
        IERC20(path[0]).safeTransfer(_amms[0].pairFor(path[0], path[1]), amounts[0]);
            
        for (uint i; i < _amms.length; i++) { // _amms.length == paths.length - 1
            (address input, address output) = (path[i], path[i + 1]);
            (uint amount0Out, uint amount1Out) = input < output ? (uint(0), amounts[i + 1]) : (amounts[i + 1], uint(0));
            address to = i < path.length - 2 ? _amms[i].pairFor(output, path[i + 2]) : recipient;
            IUniswapV2Pair(_amms[i].pairFor(input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }
    
    //like the standard router function to convert tokens to LP, but without checks that do not impact vault functions
    function add_liquidity(AmmData _amm, address pair, address token0, address token1, uint amount0, uint amount1) internal returns (uint liquidity) {
            
        (uint reserve0, uint reserve1) = GibbonLibrary.getReserves(_amm, token0, token1);

        uint amount1Optimal = GibbonLibrary.quote(amount0, reserve0, reserve1);
        if (amount1Optimal <= amount1) amount1 = amount1Optimal;
        else amount0 = GibbonLibrary.quote(amount1, reserve1, reserve0);

        IERC20(token0).safeTransfer(pair, amount0);
        IERC20(token1).safeTransfer(pair, amount1);
        return IUniswapV2Pair(pair).mint(address(this));
    }
        
    //Converts the maximum possible amount of held tokens to LP
    function add_all_liquidity(AmmData _amm, address pair, address token0, address token1) internal returns (uint liquidity) {
        uint256 token0Amt = IERC20(token0).balanceOf(address(this));
        uint256 token1Amt = IERC20(token1).balanceOf(address(this));
        if (token0Amt == 0 || token1Amt == 0) return 0;
        return add_liquidity(_amm, pair, token0, token1, token0Amt, token1Amt); //note: previously always erroneously returned zero. This value was not used and did not affect execution
    }
    
}