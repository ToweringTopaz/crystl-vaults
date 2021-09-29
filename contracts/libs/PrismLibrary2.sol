// SPDX-License-Identifier: GPL
pragma solidity 0.8.4;

import "./IUniRouter02.sol";
import "./IUniFactory.sol";
import "./PrismLibrary.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library HelperLiquidity {
    using SafeERC20 for IERC20;
        
    //based on liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);    
    function optimalMint(address pair, address tokenA, address tokenB) internal {
        (address token0, address token1) = PrismLibrary.sortTokens(tokenA, tokenB);
    
        (uint112 reserve0, uint112 reserve1,) = IUniPair(pair).getReserves();
        uint totalSupply = IUniPair(pair).totalSupply();
        
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        
        uint liquidity0 = balance0 * totalSupply / reserve0;
        uint liquidity1 = balance1 * totalSupply / reserve1;
        
        if (liquidity0 < liquidity1) {
            balance1 = reserve1 * balance0 / reserve0;
        } else if (liquidity1 < liquidity0) {
            balance0 = reserve0 * balance1 / reserve1;
        }
        
        IERC20(token0).safeTransfer(pair, balance0);
        IERC20(token1).safeTransfer(pair, balance1);
        IUniPair(pair).mint(address(this));
        
    }
}