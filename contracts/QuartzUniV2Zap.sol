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

import "./libs/LibQuartz.sol";
import "./libs/IUniRouter.sol";

contract QuartzUniV2Zap {
    using SafeERC20 for IERC20;
    using LibQuartz for VaultHealer;
    using LibQuartz for IUniRouter;
    using LibQuartz for IUniPair;
    
    uint256 public constant MINIMUM_AMOUNT = 1000;
    VaultHealer public immutable vaultHealer;

    mapping(bytes32 => bool) private approvals;

    constructor(VaultHealer _vaultHealer) {
        vaultHealer = _vaultHealer;
    }

    receive() external payable {
        require(Address.isContract(msg.sender));
    }

    function quartzInETH (uint pid, uint256 tokenAmountOutMin) external payable {
        require(msg.value >= MINIMUM_AMOUNT, 'Quartz: Insignificant input amount');
        
        address weth = vaultHealer.getRouter(pid).WETH();
        
        IWETH(weth).deposit{value: msg.value}();

        _swapAndStake(pid, tokenAmountOutMin, IERC20(weth));
    }

    function quartzIn (uint pid, uint256 tokenAmountOutMin, address tokenInAddress, uint256 tokenInAmount) external {
        require(tokenInAmount >= MINIMUM_AMOUNT, 'Quartz: Insignificant input amount');
        
        IERC20 tokenIn = IERC20(tokenInAddress);
        require(tokenIn.allowance(msg.sender, address(this)) >= tokenInAmount, 'Quartz: Input token is not approved');
        tokenIn.safeTransferFrom(msg.sender, address(this), tokenInAmount);
        require(tokenIn.balanceOf(address(this)) >= tokenInAmount, 'Quartz: Fee-on-transfer/reflect tokens not yet supported');

        _swapAndStake(pid, tokenAmountOutMin, tokenIn);
    }

    function quartzOut (uint pid, uint256 withdrawAmount) external {
        (IUniRouter router,, IUniPair pair) = vaultHealer.getRouterAndPair(pid);
        vaultHealer.withdrawFrom(pid, withdrawAmount, msg.sender, address(this)); //todo should this rather be vid, not pid? AND I need to add a from address to the function

        address weth = router.WETH();

        if (pair.token0() != weth && pair.token1() != weth) {
            return LibQuartz.removeLiquidity(address(pair), msg.sender);
        }

        LibQuartz.removeLiquidity(address(pair), msg.sender);

        address[] memory tokens = new address[](2);
        tokens[0] = pair.token0();
        tokens[1] = pair.token1();

        router.returnAssets(tokens); //returns any leftover tokens to user
    }
    
    function estimateSwap(uint pid, address tokenIn, uint256 fullInvestmentIn) external view returns(uint256 swapAmountIn, uint256 swapAmountOut, address swapTokenOut) {
        return vaultHealer.estimateSwap(pid, tokenIn, fullInvestmentIn);
    }

    function _swapAndStake(uint pid, uint256 tokenAmountOutMin, IERC20 tokenIn) private {
        (IUniRouter router,,IUniPair pair) = vaultHealer.getRouterAndPair(pid);        
        
        address token0 = pair.token0();
        address token1 = pair.token1();
        (uint256 reserveA, uint256 reserveB,) = pair.getReserves();

        uint256 swapAmountIn;
        uint256 fullInvestment = IERC20(tokenIn).balanceOf(address(this));
        _approveTokenIfNeeded(address(tokenIn), router);

        if (token0 == address(tokenIn)) {
            require(LibQuartz.hasSufficientLiquidity(token0, token1, router, MINIMUM_AMOUNT), 'Quartz: Liquidity pair reserves too low');
            swapAmountIn = router.getSwapAmount(fullInvestment, reserveA, reserveB);
            swapDirect(swapAmountIn, tokenAmountOutMin, address(tokenIn), token1, router);

        } else if (token1 == address(tokenIn)) {
            require(LibQuartz.hasSufficientLiquidity(token0, token1, router, MINIMUM_AMOUNT), 'Quartz: Liquidity pair reserves too low');
            swapAmountIn = router.getSwapAmount(fullInvestment, reserveB, reserveA);
            swapDirect(swapAmountIn, tokenAmountOutMin, address(tokenIn), token0, router);
            
        } else {
            swapAmountIn = fullInvestment/2;
            
            if(LibQuartz.hasSufficientLiquidity(token0, address(tokenIn), router, MINIMUM_AMOUNT)) {
                swapDirect(swapAmountIn, tokenAmountOutMin, address(tokenIn), token0, router);
            } else {
                swapViaWETH(swapAmountIn, tokenAmountOutMin, address(tokenIn), token0, router);
            }
            
            if(LibQuartz.hasSufficientLiquidity(token1, address(tokenIn), router, MINIMUM_AMOUNT)) {
                swapDirect(swapAmountIn, tokenAmountOutMin, address(tokenIn), token1, router);
            } else {
                swapViaWETH(swapAmountIn, tokenAmountOutMin, address(tokenIn), token1, router);
            }
        }
        
        pair.optimalMint(IERC20(token0), IERC20(token1));
        uint256 amountLiquidity = pair.balanceOf(address(this));

        _approveTokenIfNeeded(address(pair));
        vaultHealer.deposit(pid, amountLiquidity, msg.sender);

        address[] memory tokens = new address[](3);
        tokens[0] = token0;
        tokens[1] = token1;
        tokens[2] = address(tokenIn);
        router.returnAssets(tokens);
    }

    function swapDirect(uint256 swapAmountIn, uint256 tokenAmountOutMin, address tokenIn, address tokenOut, IUniRouter router) private {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        router.swapExactTokensForTokens(swapAmountIn, tokenAmountOutMin, path, address(this), type(uint256).max);
    }

    function swapViaWETH(uint256 swapAmountIn, uint256 tokenAmountOutMin, address tokenIn, address tokenOut, IUniRouter router) private {
        require(LibQuartz.hasSufficientLiquidity(tokenIn, router.WETH(), router, MINIMUM_AMOUNT), 'Quartz: Insufficient Liquidity to swap from tokenIn to WNATIVE');
        require(LibQuartz.hasSufficientLiquidity(tokenOut, router.WETH(), router, MINIMUM_AMOUNT), 'Quartz: Insufficient Liquidity to swap from WNATIVE to tokenOut');
        address[] memory path = new address[](3);
        path[0] = tokenIn;
        path[1] = router.WETH();
        path[2] = tokenOut;
        router.swapExactTokensForTokens(swapAmountIn, tokenAmountOutMin, path, address(this), type(uint256).max);
    }

    function _approveTokenIfNeeded(address token) private {
        if (!approvals[keccak256(abi.encodePacked(token,vaultHealer))]) {
            IERC20(token).safeApprove(address(vaultHealer), type(uint256).max);
            approvals[keccak256(abi.encodePacked(token,vaultHealer))] = true;
        }
    }
    function _approveTokenIfNeeded(address token, IUniRouter router) private {
        if (!approvals[keccak256(abi.encodePacked(token,router))]) {
            IERC20(token).safeApprove(address(router), type(uint256).max);
            approvals[keccak256(abi.encodePacked(token,router))] = true;
        }
    }

}