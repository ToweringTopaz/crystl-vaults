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

import {SafeERC20Upgradeable as SafeERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./HardMath.sol";
import "./IStrategy.sol";
import "./IVaultHealer.sol";
import "./IUniRouter.sol";
import "./IUniPair.sol";
import "./IWETH.sol";
import "./IUniFactory.sol";

library LibQuartz {
    using SafeERC20 for IERC20;
    using SafeERC20 for IUniPair;
    
    uint256 constant MINIMUM_AMOUNT = 1000;
    
    function getRouter(IVaultHealer vaultHealer, uint vid) internal view returns (IUniRouter) {
        (,IStrategy strat) = vaultHealer.vaultInfo(vid);
        return strat.router();
    }
    
    function getRouterAndPair(IVaultHealer vaultHealer, uint _vid) internal view returns (IUniRouter router, IStrategy strat, IUniPair pair) {
        IERC20 want;
        (want, strat) = vaultHealer.vaultInfo(_vid);
        
        pair = IUniPair(address(want));
        router = strat.router();
        require(pair.factory() == router.factory(), 'Quartz: Incompatible liquidity pair factory');
    }
    function getSwapAmount(IUniRouter router, uint256 investmentA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 swapAmount) {
        uint256 halfInvestment = investmentA / 2;
        uint256 numerator = router.getAmountOut(halfInvestment, reserveA, reserveB);
        uint256 denominator = router.quote(halfInvestment, reserveA + halfInvestment, reserveB - numerator);
        swapAmount = investmentA - HardMath.sqrt(halfInvestment * halfInvestment * numerator / denominator);
    }
    function returnAssets(IUniRouter router, IERC20[] memory tokens) internal {
        IWETH weth = router.WETH();
        uint256 balance;
        
        for (uint256 i; i < tokens.length; i++) {
            balance = tokens[i].balanceOf(address(this));
            if (balance > 0) {
                if (tokens[i] == weth) {
                    weth.withdraw(balance);
                    (bool success,) = msg.sender.call{value: balance}(new bytes(0));
                    require(success, 'Quartz: ETH transfer failed');
                } else {
                    tokens[i].safeTransfer(msg.sender, balance);
                }
            }
        }
    }
    function estimateSwap(IVaultHealer vaultHealer, uint pid, IERC20 tokenIn, uint256 fullInvestmentIn) internal view returns(uint256 swapAmountIn, uint256 swapAmountOut, IERC20 swapTokenOut) {
        (IUniRouter router,,IUniPair pair) = getRouterAndPair(vaultHealer, pid);
        
        bool isInputA = pair.token0() == tokenIn;
        require(isInputA || pair.token1() == tokenIn, 'Quartz: Input token not present in liquidity pair');

        (uint256 reserveA, uint256 reserveB,) = pair.getReserves();
        (reserveA, reserveB) = isInputA ? (reserveA, reserveB) : (reserveB, reserveA);

        swapAmountIn = getSwapAmount(router, fullInvestmentIn, reserveA, reserveB);
        swapAmountOut = router.getAmountOut(swapAmountIn, reserveA, reserveB);
        swapTokenOut = isInputA ? pair.token1() : pair.token0();
    }

    function removeLiquidity(IUniPair pair, address to) internal {
        pair.safeTransfer(address(pair), pair.balanceOf(address(this)));
        (uint256 amount0, uint256 amount1) = pair.burn(to);

        require(amount0 >= MINIMUM_AMOUNT, 'Quartz: INSUFFICIENT_A_AMOUNT');
        require(amount1 >= MINIMUM_AMOUNT, 'Quartz: INSUFFICIENT_B_AMOUNT');
    }

    function optimalMint(IUniPair pair, IERC20 token0, IERC20 token1) internal returns (uint liquidity) {
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
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

    function hasSufficientLiquidity(IERC20 token0, IERC20 token1, IUniRouter router, uint256 min_amount) internal view returns (bool hasLiquidity) {
        IUniFactory factory = router.factory();
        IUniPair pair = IUniPair(factory.getPair(token0, token1));
        (uint256 reserveA, uint256 reserveB,) = pair.getReserves();

        if (reserveA > min_amount && reserveB > min_amount) {
            return hasLiquidity = true;
        } else {
            return hasLiquidity = false;
        }
    }

}