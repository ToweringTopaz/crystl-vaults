// SPDX-License-Identifier: GPLv2

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 2 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.

// @author Wivern for Beefy.Finance, ToweringTopaz for Crystl.Finance
// @notice This contract adds liquidity to Uniswap V2 compatible liquidity pair pools and stake.

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./Babylonian.sol";
import "./IStrategy.sol";
import "./IVaultHealer.sol";
import './IUniRouter02.sol';
import "./IUniswapV2Pair.sol";
import "./IWETH.sol";
import "./IUniswapV2Factory.sol";

library LibQuartz {
    using SafeERC20 for IERC20;
    
    uint256 constant MINIMUM_AMOUNT = 1000;
    
    function getRouter(IVaultHealer vaultHealer, uint pid) internal view returns (IUniRouter02) {
        (,IStrategy strat) = vaultHealer.poolInfo(pid);
        return IUniRouter02(strat.uniRouterAddress());
    }
    
    function getRouterAndPair(IVaultHealer vaultHealer, uint _pid) internal view returns (IUniRouter02 router, IStrategy strat, IUniswapV2Pair pair) {
        IERC20 want;
        (want, strat) = vaultHealer.poolInfo(_pid);
        
        pair = IUniswapV2Pair(address(want));
        router = IUniRouter02(strat.uniRouterAddress());
        require(pair.factory() == router.factory(), 'Quartz: Incompatible liquidity pair factory');
    }
    function getSwapAmount(IUniRouter02 router, uint256 investmentA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 swapAmount) {
        uint256 halfInvestment = investmentA / 2;
        uint256 numerator = router.getAmountOut(halfInvestment, reserveA, reserveB);
        uint256 denominator = router.quote(halfInvestment, reserveA + halfInvestment, reserveB - numerator);
        swapAmount = investmentA - Babylonian.sqrt(halfInvestment * halfInvestment * numerator / denominator);
    }
    function returnAssets(IUniRouter02 router, address[] memory tokens) internal {
        address weth = router.WETH();
        uint256 balance;
        
        for (uint256 i; i < tokens.length; i++) {
            balance = IERC20(tokens[i]).balanceOf(address(this));
            if (balance > 0) {
                if (tokens[i] == weth) {
                    IWETH(weth).withdraw(balance);
                    (bool success,) = msg.sender.call{value: balance}(new bytes(0));
                    require(success, 'Quartz: ETH transfer failed');
                } else {
                    IERC20(tokens[i]).safeTransfer(msg.sender, balance);
                }
            }
        }
    }
    function estimateSwap(IVaultHealer vaultHealer, uint pid, address tokenIn, uint256 fullInvestmentIn) internal view returns(uint256 swapAmountIn, uint256 swapAmountOut, address swapTokenOut) {
        (IUniRouter02 router,,IUniswapV2Pair pair) = getRouterAndPair(vaultHealer, pid);
        
        bool isInputA = pair.token0() == tokenIn;
        require(isInputA || pair.token1() == tokenIn, 'Quartz: Input token not present in liquidity pair');

        (uint256 reserveA, uint256 reserveB,) = pair.getReserves();
        (reserveA, reserveB) = isInputA ? (reserveA, reserveB) : (reserveB, reserveA);

        swapAmountIn = getSwapAmount(router, fullInvestmentIn, reserveA, reserveB);
        swapAmountOut = router.getAmountOut(swapAmountIn, reserveA, reserveB);
        swapTokenOut = isInputA ? pair.token1() : pair.token0();
    }
    function removeLiquidity(address pair, address to) internal {
        IERC20(pair).safeTransfer(pair, IERC20(pair).balanceOf(address(this)));
        (uint256 amount0, uint256 amount1) = IUniswapV2Pair(pair).burn(to);

        require(amount0 >= MINIMUM_AMOUNT, 'Quartz: INSUFFICIENT_A_AMOUNT');
        require(amount1 >= MINIMUM_AMOUNT, 'Quartz: INSUFFICIENT_B_AMOUNT');
    }
    function optimalMint(IUniswapV2Pair pair, IERC20 token0, IERC20 token1) internal returns (uint liquidity) {
        //already sorted here
        //(IERC20 token0, IERC20 token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        uint totalSupply = pair.totalSupply();
        
        uint balance0 = token0.balanceOf(address(this));
        uint balance1 = token1.balanceOf(address(this));

        uint liquidity0 = balance0 * totalSupply / reserve0;
        uint liquidity1 = balance1 * totalSupply / reserve1;

        if (liquidity0 < liquidity1) {
            balance1 = reserve1 * balance0 / reserve0;
        } else {
            balance0 = reserve0 * balance1 / reserve1;
        }

        token0.safeTransfer(address(pair), balance0);
        token1.safeTransfer(address(pair), balance1);
        liquidity = pair.mint(address(this));
    }

    function hasSufficientLiquidity(address token0, address token1, IUniRouter02 router, uint256 min_amount) internal view returns (bool hasLiquidity) {
        address factory_address = router.factory();
        IUniswapV2Factory factory = IUniswapV2Factory(factory_address);
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(token0, token1));
        (uint256 reserveA, uint256 reserveB,) = pair.getReserves();

        if (reserveA > min_amount && reserveB > min_amount) {
            return hasLiquidity = true;
        } else {
            return hasLiquidity = false;
        }
    }

}