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

contract QuartzUniV2Zap {
    using SafeERC20 for IERC20;
    using LibQuartz for IVaultHealer;
    using LibQuartz for IUniRouter02;
    using LibQuartz for IUniswapV2Pair;
    
    uint256 public constant MINIMUM_AMOUNT = 1000;
    IVaultHealer public immutable vaultHealer;

    mapping(bytes32 => bool) private approvals;

    constructor(IVaultHealer _vaultHealer) {
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

    function quartzIn (uint pid, uint256 tokenAmountOutMin, IERC20 tokenIn, uint256 tokenInAmount) external {
        require(tokenInAmount >= MINIMUM_AMOUNT, 'Quartz: Insignificant input amount');
        require(tokenIn.allowance(msg.sender, address(this)) >= tokenInAmount, 'Quartz: Input token is not approved');

        tokenIn.safeTransferFrom(msg.sender, address(this), tokenInAmount);
        require(tokenIn.balanceOf(address(this)) >= tokenInAmount, 'Quartz: Fee-on-transfer/reflect tokens not yet supported');

        _swapAndStake(pid, tokenAmountOutMin, tokenIn);
    }

    function quartzOut (uint pid, uint256 withdrawAmount) external {
        (IUniRouter02 router,, IUniswapV2Pair pair) = vaultHealer.getRouterAndPair(pid);

        address weth = router.WETH();

        IERC20(address(pair)).safeTransferFrom(msg.sender, address(this), withdrawAmount);

        if (pair.token0() != weth && pair.token1() != weth) {
            return LibQuartz.removeLiquidity(address(pair), msg.sender);
        }

        LibQuartz.removeLiquidity(address(pair), address(this));

        address[] memory tokens = new address[](2);
        tokens[0] = pair.token0();
        tokens[1] = pair.token1();
        
        router.returnAssets(tokens);
    }
    
    function estimateSwap(uint pid, address tokenIn, uint256 fullInvestmentIn) external view returns(uint256 swapAmountIn, uint256 swapAmountOut, address swapTokenOut) {
        return vaultHealer.estimateSwap(pid, tokenIn, fullInvestmentIn);
    }

    function _swapAndStake(uint pid, uint256 tokenAmountOutMin, IERC20 tokenIn) private {
        (IUniRouter02 router,,IUniswapV2Pair pair) = vaultHealer.getRouterAndPair(pid);

        (uint256 reserveA, uint256 reserveB,) = pair.getReserves();
        require(reserveA > MINIMUM_AMOUNT && reserveB > MINIMUM_AMOUNT, 'Quartz: Liquidity pair reserves too low');
        
        address token0 = pair.token0();
        address token1 = pair.token1();

        address[] memory path = new address[](2);
        path[0] = address(tokenIn);
        uint256 swapAmountIn;
        uint256 fullInvestment = IERC20(tokenIn).balanceOf(address(this));
        
        if (token0 == address(tokenIn)) {
            path[1] = token1;
            swapAmountIn = router.getSwapAmount(fullInvestment, reserveA, reserveB);
        } else {
            require(token1 == address(tokenIn), 'Quartz: Input token not present in liquidity pair');
            path[1] = token0;
            swapAmountIn = router.getSwapAmount(fullInvestment, reserveB, reserveA);
        }
        
        _approveTokenIfNeeded(address(tokenIn), router);
        router.swapExactTokensForTokens(swapAmountIn, tokenAmountOutMin, path, address(this), type(uint256).max);

        pair.optimalMint(IERC20(token0), IERC20(token1));
        uint256 amountLiquidity = pair.balanceOf(address(this));

        _approveTokenIfNeeded(address(pair));
        vaultHealer.deposit(pid, amountLiquidity, msg.sender);

        assert(pair.balanceOf(address(this)) == 0);
        router.returnAssets(path);
    }

    function _approveTokenIfNeeded(address token) private {
        if (!approvals[keccak256(abi.encodePacked(token,vaultHealer))]) {
            IERC20(token).safeApprove(address(vaultHealer), type(uint256).max);
            approvals[keccak256(abi.encodePacked(token,vaultHealer))] = true;
        }
    }
    function _approveTokenIfNeeded(address token, IUniRouter02 router) private {
        if (!approvals[keccak256(abi.encodePacked(token,router))]) {
            IERC20(token).safeApprove(address(vaultHealer), type(uint256).max);
            approvals[keccak256(abi.encodePacked(token,router))] = true;
        }
    }

}