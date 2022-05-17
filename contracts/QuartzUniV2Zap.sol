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

import "./libraries/LibQuartz.sol";

contract QuartzUniV2Zap {
    using SafeERC20 for IERC20;
    using LibQuartz for IVaultHealer;
    using LibQuartz for IUniRouter;
    using LibQuartz for IUniPair;
    using VaultChonk for IVaultHealer;

    uint256 public constant MINIMUM_AMOUNT = 1000;
    IVaultHealer public immutable vaultHealer;

    mapping(bytes32 => bool) private approvals;

    constructor(address _vaultHealer) {
        vaultHealer = IVaultHealer(_vaultHealer);
    }

    receive() external payable {
        require(Address.isContract(msg.sender));
    }

    function quartzInETH (uint vid, uint256 tokenAmountOutMin) external payable {
        require(msg.value >= MINIMUM_AMOUNT, 'Quartz: Insignificant input amount');
        
        IWETH weth = vaultHealer.getRouter(vid).WETH();
        
        weth.deposit{value: msg.value}();

        _swapAndStake(vid, tokenAmountOutMin, weth);
    }

    function quartzIn (uint vid, uint256 tokenAmountOutMin, address tokenInAddress, uint256 tokenInAmount) external {
        require(tokenInAmount >= MINIMUM_AMOUNT, 'Quartz: Insignificant input amount');
        
        IERC20 tokenIn = IERC20(tokenInAddress);
        require(tokenIn.allowance(msg.sender, address(this)) >= tokenInAmount, 'Quartz: Input token is not approved');
        tokenIn.safeTransferFrom(msg.sender, address(this), tokenInAmount);
        require(tokenIn.balanceOf(address(this)) >= tokenInAmount, 'Quartz: Fee-on-transfer/reflect tokens not yet supported');

        _swapAndStake(vid, tokenAmountOutMin, tokenIn);
    }

    //should only happen when this contract deposits as a maximizer
    function onERC1155Received(
        address operator, address /*from*/, uint256 /*id*/, uint256 /*amount*/, bytes calldata) external view returns (bytes4) {
        //if (msg.sender != address(vaultHealer)) revert("Quartz: Incorrect ERC1155 issuer");
        if (operator != address(this)) revert("Quartz: Improper ERC1155 transfer"); 
        return 0xf23a6e61;
    }

    function quartzOut (uint vid, uint256 withdrawAmount) public {
        (IUniRouter router,, IUniPair pair) = vaultHealer.getRouterAndPair(vid);
        if (withdrawAmount > 0) {
            withdrawAmount = withdrawAmount * vaultHealer.totalSupply(vid) / vaultHealer.strat(vid).wantLockedTotal();
            uint fullBalance = vaultHealer.balanceOf(msg.sender, vid);
            if (withdrawAmount > fullBalance) withdrawAmount = fullBalance;
            vaultHealer.safeTransferFrom(msg.sender, address(this), vid, withdrawAmount, "");
        }

        if (vaultHealer.balanceOf(address(this), vid) > 0) vaultHealer.withdraw(vid, type(uint).max, "");
        uint targetVid = vid >> 16;
        if (targetVid > 0) quartzOut(targetVid, 0);

        IWETH weth = router.WETH();

        IERC20 token0;
        IERC20 token1;
        try pair.token0() returns (IERC20 _token0) {
            token0 = _token0;
            token1 = pair.token1();
            if (token0 != weth && token1 != weth) {
                pair.burn(msg.sender);
            } else {
                pair.burn(address(this));
                router.returnAsset(token0); //returns any leftover tokens to user
                router.returnAsset(token1); //returns any leftover tokens to user
            }
        } catch {
            router.returnAsset(pair);
        }
    }
    
    function estimateSwap(uint vid, IERC20 tokenIn, uint256 fullInvestmentIn) external view returns(uint256 swapAmountIn, uint256 swapAmountOut, IERC20 swapTokenOut) {
        return vaultHealer.estimateSwap(vid, tokenIn, fullInvestmentIn);
    }

    function _swapAndStake(uint vid, uint256 tokenAmountOutMin, IERC20 tokenIn) private {
        (IUniRouter router,,IUniPair pair) = vaultHealer.getRouterAndPair(vid);        
        
        IERC20 token0 = pair.token0();
        IERC20 token1 = pair.token1();
        (uint256 reserveA, uint256 reserveB,) = pair.getReserves();

        uint256 swapAmountIn;
        uint256 fullInvestment = tokenIn.balanceOf(address(this));
        _approveTokenIfNeeded(tokenIn, router);

        if (token0 == tokenIn) {
            require(LibQuartz.hasSufficientLiquidity(token0, token1, router, MINIMUM_AMOUNT), 'Quartz: Liquidity pair reserves too low');
            swapAmountIn = router.getSwapAmount(fullInvestment, reserveA, reserveB);
            swapDirect(swapAmountIn, tokenAmountOutMin, tokenIn, token1, router);

        } else if (token1 == tokenIn) {
            require(LibQuartz.hasSufficientLiquidity(token0, token1, router, MINIMUM_AMOUNT), 'Quartz: Liquidity pair reserves too low');
            swapAmountIn = router.getSwapAmount(fullInvestment, reserveB, reserveA);
            swapDirect(swapAmountIn, tokenAmountOutMin, tokenIn, token0, router);
            
        } else {
            swapAmountIn = fullInvestment/2;
            
            if(LibQuartz.hasSufficientLiquidity(token0, tokenIn, router, MINIMUM_AMOUNT)) {
                swapDirect(swapAmountIn, tokenAmountOutMin, tokenIn, token0, router);
            } else {
                swapViaWETH(swapAmountIn, tokenAmountOutMin, tokenIn, token0, router);
            }
            
            if(LibQuartz.hasSufficientLiquidity(token1, tokenIn, router, MINIMUM_AMOUNT)) {
                swapDirect(swapAmountIn, tokenAmountOutMin, tokenIn, token1, router);
            } else {
                swapViaWETH(swapAmountIn, tokenAmountOutMin, tokenIn, token1, router);
            }
        }
        
        pair.optimalMint(IERC20(token0), IERC20(token1));

        _approveTokenIfNeeded(pair);
        uint balance = pair.balanceOf(address(this));
        vaultHealer.deposit(vid, balance, "");
        
        balance = vaultHealer.balanceOf(address(this), vid);
        vaultHealer.safeTransferFrom(address(this), msg.sender, vid, balance, "");
        router.returnAsset(token0);
        router.returnAsset(token1);
        router.returnAsset(tokenIn);
    }

    function swapDirect(uint256 swapAmountIn, uint256 tokenAmountOutMin, IERC20 tokenIn, IERC20 tokenOut, IUniRouter router) private {
        IERC20[] memory path = new IERC20[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        router.swapExactTokensForTokens(swapAmountIn, tokenAmountOutMin, path, address(this), type(uint256).max);
    }

    function swapViaWETH(uint256 swapAmountIn, uint256 tokenAmountOutMin, IERC20 tokenIn, IERC20 tokenOut, IUniRouter router) private {
        require(LibQuartz.hasSufficientLiquidity(IERC20(tokenIn), router.WETH(), router, MINIMUM_AMOUNT), 'Quartz: Insufficient Liquidity to swap from tokenIn to WNATIVE');
        require(LibQuartz.hasSufficientLiquidity(IERC20(tokenOut), router.WETH(), router, MINIMUM_AMOUNT), 'Quartz: Insufficient Liquidity to swap from WNATIVE to tokenOut');
        IERC20[] memory path = new IERC20[](3);
        path[0] = tokenIn;
        path[1] = router.WETH();
        path[2] = tokenOut;
        router.swapExactTokensForTokens(swapAmountIn, tokenAmountOutMin, path, address(this), type(uint256).max);
    }

    function _approveTokenIfNeeded(IERC20 token) private {
        if (!approvals[keccak256(abi.encodePacked(token,vaultHealer))]) {
            token.safeApprove(address(vaultHealer), type(uint256).max);
            approvals[keccak256(abi.encodePacked(token,vaultHealer))] = true;
        }
    }
    function _approveTokenIfNeeded(IERC20 token, IUniRouter router) private {
        if (!approvals[keccak256(abi.encodePacked(token,router))]) {
            token.safeApprove(address(router), type(uint256).max);
            approvals[keccak256(abi.encodePacked(token,router))] = true;
        } 
    }

}