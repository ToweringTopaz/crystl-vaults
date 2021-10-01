// SPDX-License-Identifier: GPL
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./PrismLibrary.sol";

import "hardhat/console.sol";

library PrismLibrary2 {
    using SafeERC20 for IERC20;

    //based on liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);    
    function optimalMint(address pair, address tokenA, address tokenB) internal returns (uint liquidity) {
        (address token0, address token1) = PrismLibrary.sortTokens(tokenA, tokenB);
        console.log("optimalMint: token0 is %s and token1 is %s", token0, token1);
        
        (uint112 reserve0, uint112 reserve1,) = IUniPair(pair).getReserves();
        console.log("optimalMint: reserve0 is %s and reserve1 is %s", reserve0, reserve1);
        uint totalSupply = IUniPair(pair).totalSupply();
        
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        console.log("optimalMint: balance0 is %s and balance1 is %s", balance0, balance1);
        
        uint liquidity0 = balance0 * totalSupply / reserve0;
        uint liquidity1 = balance1 * totalSupply / reserve1;
        console.log("optimalMint: liquidity0 is %s and liquidity1 is %s", liquidity0, liquidity1);
        
        if (liquidity0 < liquidity1) {
            balance1 = reserve1 * balance0 / reserve0;
        } else if (liquidity1 < liquidity0) {
            balance0 = reserve0 * balance1 / reserve1;
        }
        console.log("optimalMint: balance0 is %s and balance1 is %s", balance0, balance1);
        
        IERC20(token0).safeTransfer(pair, balance0);
        IERC20(token1).safeTransfer(pair, balance1);
        liquidity = IUniPair(pair).mint(address(this));
        console.log("final liquidity is %s", liquidity);
        
    }
}