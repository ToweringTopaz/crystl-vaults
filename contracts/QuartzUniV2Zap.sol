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

pragma solidity ^0.8.14;

import "./libraries/LibQuartz.sol";

contract QuartzUniV2Zap {
    using SafeERC20 for IERC20;
    using LibQuartz for IVaultHealer;
    using VaultChonk for IVaultHealer;

    uint256 public constant MINIMUM_AMOUNT = 1000;
    IVaultHealer public immutable vaultHealer;

    mapping(IERC20 => bool) private approvals;

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
        (IUniRouter router,, IUniPair pair, bool isPair) = vaultHealer.getRouterAndPair(vid);
        uint balance;
        if (withdrawAmount > 0) {
            uint[4] memory data = vaultHealer.tokenData(msg.sender, asSingletonArray(vid))[0];
            withdrawAmount = withdrawAmount * data[3] / data[2]; //amt*supply/wlt
            balance = data[1]; //shares
            withdrawAmount = withdrawAmount > balance ? balance : withdrawAmount;
            vaultHealer.safeTransferFrom(msg.sender, address(this), vid, withdrawAmount, "");
        }

        if (balance > 0) vaultHealer.withdraw(vid, type(uint).max, "");
        uint targetVid = vid >> 16;
        if (targetVid > 0) quartzOut(targetVid, 0);

        IWETH weth = router.WETH();

        if (isPair) {
            uint lpBalance = pair.balanceOf(address(this));
            if (lpBalance > 0) {
                pair.transfer(address(pair), lpBalance);

                IERC20 token0 = pair.token0();
                IERC20 token1 = pair.token1();
                if (token0 != weth && token1 != weth) {
                    pair.burn(msg.sender);
                } else {
                    pair.burn(address(this));
                    returnAsset(token0, weth); //returns any leftover tokens to user
                    returnAsset(token1, weth); //returns any leftover tokens to user
                }
            }
        } else {
            returnAsset(pair, weth);
        }
    }

    function _swapAndStake(uint vid, uint256 tokenAmountOutMin, IERC20 tokenIn) private {
        (IUniRouter router,,IUniPair pair, bool isPair) = vaultHealer.getRouterAndPair(vid);        
        
        IWETH weth = router.WETH();

        if (isPair) {
            IERC20 token0 = pair.token0();
            IERC20 token1 = pair.token1();

        //_approveTokenIfNeeded(tokenIn, router);

            if (token0 == tokenIn) {
                (uint256 reserveA, uint256 reserveB,) = pair.getReserves();
                swapDirect(LibQuartz.getSwapAmount(router, tokenIn.balanceOf(address(this)), reserveA, reserveB), tokenAmountOutMin, tokenIn, token1, router);

            } else if (token1 == tokenIn) {
                (uint256 reserveA, uint256 reserveB,) = pair.getReserves();
                swapDirect(LibQuartz.getSwapAmount(router, tokenIn.balanceOf(address(this)), reserveB, reserveA), tokenAmountOutMin, tokenIn, token0, router);
                
            } else {
                uint swapAmountIn = tokenIn.balanceOf(address(this))/2;
                
                if(LibQuartz.hasSufficientLiquidity(token0, tokenIn, router, MINIMUM_AMOUNT)) {
                    swapDirect(swapAmountIn, tokenAmountOutMin, tokenIn, token0, router);
                } else {
                    swapViaToken(swapAmountIn, tokenAmountOutMin, tokenIn, weth, token0, router);
                }
                
                if(LibQuartz.hasSufficientLiquidity(token1, tokenIn, router, MINIMUM_AMOUNT)) {
                    swapDirect(swapAmountIn, tokenAmountOutMin, tokenIn, token1, router);
                } else {
                    swapViaToken(swapAmountIn, tokenAmountOutMin, tokenIn, weth, token1, router);
                }
            }
            
            LibQuartz.optimalMint(pair, token0, token1);
            returnAsset(token0, weth);
            returnAsset(token1, weth);
        } else {
            uint swapAmountIn = tokenIn.balanceOf(address(this));
            if(LibQuartz.hasSufficientLiquidity(pair, tokenIn, router, MINIMUM_AMOUNT)) {
                swapDirect(swapAmountIn, tokenAmountOutMin, tokenIn, pair, router);
            } else {
                swapViaToken(swapAmountIn, tokenAmountOutMin, tokenIn, weth, pair, router);
            }
        }

        _approveTokenIfNeeded(pair);
        uint balance = pair.balanceOf(address(this));
        vaultHealer.deposit(vid, balance, "");
        
        balance = vaultHealer.balanceOf(address(this), vid);
        vaultHealer.safeTransferFrom(address(this), msg.sender, vid, balance, "");

        returnAsset(tokenIn, weth);
    }

    function swapDirect(uint256 swapAmountIn, uint256 tokenAmountOutMin, IERC20 tokenIn, IERC20 tokenOut, IUniRouter router) private {
        LibQuartz.swapDirect(router, swapAmountIn, tokenIn, tokenOut, tokenAmountOutMin);
    }

    function swapViaToken(uint256 swapAmountIn, uint256 tokenAmountOutMin, IERC20 tokenIn, IERC20 middleToken, IERC20 tokenOut, IUniRouter router) private {
        LibQuartz.swapViaToken(router, swapAmountIn, tokenIn, middleToken, tokenOut, tokenAmountOutMin);
    }
    function returnAsset(IERC20 token, IWETH weth) internal {
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) return;
        
        if (token == weth) {
            weth.withdraw(balance);
            (bool success,) = msg.sender.call{value: address(this).balance}(new bytes(0));
            require(success, 'Quartz: ETH transfer failed');
        } else {
            token.safeTransfer(msg.sender, balance);
        }
    }

    function _approveTokenIfNeeded(IERC20 token) private {
        if (!approvals[token]) {
            token.safeApprove(address(vaultHealer), type(uint256).max);
            approvals[token] = true;
        }
    }

    function asSingletonArray(uint256 n) internal pure returns (uint256[] memory tempArray) {
        tempArray = new uint256[](1);
        tempArray[0] = n;
    }

    //This contract should not hold ERC20 tokens at the end of a transaction. If this happens due to some error, this will send the tokens to the treasury, where they
    //can be disbursed.
    function rescue(address token) external {
        (address receiver,) = vaultHealer.vaultFeeManager().getWithdrawFee(0);
        if (receiver == address(0)) receiver = msg.sender;
        IERC20(token).transfer(receiver, IERC20(token).balanceOf(address(this)));
    }

}