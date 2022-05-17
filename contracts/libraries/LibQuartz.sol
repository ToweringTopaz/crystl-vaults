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
import "./VaultChonk.sol";
import "../interfaces/IUniRouter.sol";

library LibQuartz {
    using SafeERC20 for IERC20;
    using SafeERC20 for IUniPair;
    using VaultChonk for IVaultHealer;

    uint256 constant MINIMUM_AMOUNT = 1000;
    
    function getRouter(IVaultHealer vaultHealer, uint vid) internal view returns (IUniRouter) {
        return vaultHealer.strat(vid).router();
    }
    
    function getRouterAndPair(IVaultHealer vaultHealer, uint _vid) internal view returns (IUniRouter router, IStrategy strat, IUniPair pair, bool valid) {
        strat = vaultHealer.strat(_vid);
        router = strat.router();
        pair = IUniPair(address(strat.wantToken()));

        try pair.factory() returns (IUniFactory _f) {
            valid = _f == router.factory();
        } catch {

        }
    }
    function getSwapAmount(IUniRouter router, uint256 investmentA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 swapAmount) {
        uint256 halfInvestment = investmentA / 2;
        uint256 numerator = router.getAmountOut(halfInvestment, reserveA, reserveB);
        uint256 denominator = router.quote(halfInvestment, reserveA + halfInvestment, reserveB - numerator);
        swapAmount = investmentA - sqrt(halfInvestment * halfInvestment * numerator / denominator);
    }
    function returnAssets(IUniRouter router, IERC20[] memory tokens) internal {
        IWETH weth = router.WETH();
        
        
        for (uint256 i; i < tokens.length; i++) {
            uint256 balance = tokens[i].balanceOf(address(this));
            if (balance == 0) continue;
            if (tokens[i] == weth) {
                weth.withdraw(balance);
                (bool success,) = msg.sender.call{value: balance}(new bytes(0));
                require(success, 'Quartz: ETH transfer failed');
            } else {
                tokens[i].safeTransfer(msg.sender, balance);
            }
        }
    
    }

    function swapDirect(
        IUniRouter _router,
        uint256 _amountIn,
        IERC20 input,
        IERC20 output,
        uint amountOutMin
    ) internal returns (uint amountOutput) {
        IUniFactory factory = _router.factory();

        IUniPair pair = factory.getPair(input, output);
        input.safeTransfer(address(pair), _amountIn);
        uint balanceBefore = output.balanceOf(address(this));

        bool inputIsToken0 = input < output;
        
        (uint reserve0, uint reserve1,) = pair.getReserves();

        (uint reserveInput, uint reserveOutput) = inputIsToken0 ? (reserve0, reserve1) : (reserve1, reserve0);
        uint amountInput = input.balanceOf(address(pair)) - reserveInput;
        amountOutput = _router.getAmountOut(amountInput, reserveInput, reserveOutput);

        (uint amount0Out, uint amount1Out) = inputIsToken0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
        
        pair.swap(amount0Out, amount1Out, address(this), "");
    
        if (output.balanceOf(address(this)) <= amountOutMin + balanceBefore) {
            unchecked {
                revert IStrategy.InsufficientOutputAmount(output.balanceOf(address(this)) - balanceBefore, amountOutMin);
            }
        }
    }

    function swapViaToken(
        IUniRouter _router,
        uint256 _amountIn,
        IERC20 input,
        IERC20 middle,
        IERC20 output,
        uint amountOutMin
    ) internal returns (uint amountOutput) {
        IUniFactory factory = _router.factory();

        IUniPair pairA = factory.getPair(input, middle);
        IUniPair pairB = factory.getPair(middle, output);        
        input.safeTransfer(address(pairA), _amountIn);

        uint balanceBefore = output.balanceOf(address(this));

        {
            {
                (uint reserve0, uint reserve1,) = pairA.getReserves();        
                (uint reserveInput, uint reserveOutput) = (input < middle) ? (reserve0, reserve1) : (reserve1, reserve0);
                uint amountInput = input.balanceOf(address(pairA)) - reserveInput;
                amountOutput = _router.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint amount0Out, uint amount1Out) = (input < middle) ? (uint(0), amountOutput) : (amountOutput, uint(0));
            pairA.swap(amount0Out, amount1Out, address(pairB), "");
        }
        {
            {
                (uint reserve0, uint reserve1,) = pairB.getReserves();
                (uint reserveInput, uint reserveOutput) = (middle < output) ? (reserve0, reserve1) : (reserve1, reserve0);
                uint amountInput = middle.balanceOf(address(pairB)) - reserveInput;
                amountOutput = _router.getAmountOut(amountInput, reserveInput, reserveOutput);
            }

            (uint amount0Out, uint amount1Out) = (middle < output) ? (uint(0), amountOutput) : (amountOutput, uint(0));
            pairB.swap(amount0Out, amount1Out, address(this), "");
        }

        if (output.balanceOf(address(this)) <= amountOutMin + balanceBefore) {
            unchecked {
                revert IStrategy.InsufficientOutputAmount(output.balanceOf(address(this)) - balanceBefore, amountOutMin);
            }
        }
    }

    function estimateSwap(IVaultHealer vaultHealer, uint pid, IERC20 tokenIn, uint256 fullInvestmentIn) internal view returns(uint256 swapAmountIn, uint256 swapAmountOut, IERC20 swapTokenOut) {
        (IUniRouter router,,IUniPair pair,bool isPair) = getRouterAndPair(vaultHealer, pid);
        
        require(isPair, "Quartz: Cannot estimate swap for non-LP token");

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
        require(address(token0) != address(0), "LibQuartz: token0 cannot be the zero address");
        require(address(token1) != address(0), "LibQuartz: token1 cannot be the zero address");
        IUniPair pair = IUniPair(factory.getPair(token0, token1));
        if (address(pair) == address(0)) return false; //pair hasn't been created, so zero liquidity
		
        (uint256 reserveA, uint256 reserveB,) = pair.getReserves();

        if (reserveA > min_amount && reserveB > min_amount) {
            return hasLiquidity = true;
        } else {
            return hasLiquidity = false;
        }
    }

    // credit for this implementation goes to
    // https://github.com/abdk-consulting/abdk-libraries-solidity/blob/master/ABDKMath64x64.sol#L687
    function sqrt(uint256 x) internal pure returns (uint256) {
        unchecked { //impossible for any of this to overflow
            if (x == 0) return 0;
            // this block is equivalent to r = uint256(1) << (BitMath.mostSignificantBit(x) / 2);
            // however that code costs significantly more gas
            uint256 xx = x;
            uint256 r = 1;
            if (xx >= 0x100000000000000000000000000000000) {
                xx >>= 128;
                r <<= 64;
            }
            if (xx >= 0x10000000000000000) {
                xx >>= 64;
                r <<= 32;
            }
            if (xx >= 0x100000000) {
                xx >>= 32;
                r <<= 16;
            }
            if (xx >= 0x10000) {
                xx >>= 16;
                r <<= 8;
            }
            if (xx >= 0x100) {
                xx >>= 8;
                r <<= 4;
            }
            if (xx >= 0x10) {
                xx >>= 4;
                r <<= 2;
            }
            if (xx >= 0x8) {
                r <<= 1;
            }
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1; // Seven iterations should be enough
            uint256 r1 = x / r;
            return (r < r1 ? r : r1);
        }
    }

}