// SPDX-License-Identifier: GPL

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./interfaces/IApePair.sol";
import { ApeLibrary } from  "./libraries/ApeLibrary.sol";

abstract contract GibbonRouter {
    using SafeERC20 for IERC20;
    
    address constant FACTORY_ADDRESS = 0xCf083Be4164828f00cAE704EC15a36D711491284;
    
    function _swap(
        uint amountIn,
        address[] memory path,
        address recipient
    ) internal {
        
        if (amountIn == 0) return;
        //the common case of the desired token being the token we already have
        if (path.length == 1) {
            IERC20(path[0]).safeTransfer(recipient, amountIn);
            return;
        }
        
        uint[] memory amounts = ApeLibrary.getAmountsOut(FACTORY_ADDRESS, amountIn, path);
        
        IERC20(path[0]).safeTransfer(ApeLibrary.pairFor(FACTORY_ADDRESS, path[0], path[1]), amounts[0]);
            
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (uint amount0Out, uint amount1Out) = input < output ? (uint(0), amounts[i + 1]) : (amounts[i + 1], uint(0));
            address to = i < path.length - 2 ? ApeLibrary.pairFor(FACTORY_ADDRESS, output, path[i + 2]) : recipient;
            IApePair(ApeLibrary.pairFor(FACTORY_ADDRESS, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }
    
    function _add_liquidity(address pair, address token0, address token1, uint amount0, uint amount1) internal returns (uint liquidity) {
            
        (uint reserve0, uint reserve1) = ApeLibrary.getReserves(FACTORY_ADDRESS, token0, token1);

        uint amount1Optimal = ApeLibrary.quote(amount0, reserve0, reserve1);
        if (amount1Optimal <= amount1) amount1 = amount1Optimal;
        else amount0 = ApeLibrary.quote(amount1, reserve1, reserve0);

        IERC20(token0).safeTransfer(pair, amount0);
        IERC20(token1).safeTransfer(pair, amount1);
        return IApePair(pair).mint(address(this));
        }
        
    //Converts the maximum possible amount of held tokens to LP 
    function add_all_liquidity(address pair, address token0, address token1) internal returns (uint liquidity) {
        uint256 token0Amt = IERC20(token0).balanceOf(address(this));
        uint256 token1Amt = IERC20(token1).balanceOf(address(this));
        if (token0Amt == 0 || token1Amt == 0) return 0;
        _add_liquidity(pair, token0, token1, token0Amt, token1Amt);
    }
}
