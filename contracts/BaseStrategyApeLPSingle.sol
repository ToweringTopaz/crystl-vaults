// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "./BaseStrategy.sol";

abstract contract BaseStrategyApeLPSingle is BaseStrategy {
    using GibbonRouter for AmmData;
        
    address public immutable token0Address;
    address public immutable token1Address;
    
    address[] public earnedToToken0Path;
    address[] public earnedToToken1Path;
    address[] public token0ToEarnedPath;
    address[] public token1ToEarnedPath;

    constructor (AmmData _farmAMM,
        address _wantAddress, 
        address _earnedAddress, 
        address _vaultHealerAddress)  
        BaseStrategy(_farmAMM, _wantAddress, _earnedAddress, _vaultHealerAddress) 
    {
        token0Address = IUniswapV2Pair(_wantAddress).token0();
        token1Address = IUniswapV2Pair(_wantAddress).token1();
    }

    function _vaultHarvest() internal virtual;

    function convertDustToEarned() external onlyGov {
        // Converts dust tokens into earned tokens, which will be reinvested on the next earn().

        // Converts token0 dust (if any) to earned tokens
        uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
        if (token0Amt > 0 && token0Address != earnedAddress) {
            // Swap all dust tokens to earned tokens
            farmAMM.swap(
                token0Amt,
                token0ToEarnedPath,
                address(this)
            );
        }

        // Converts token1 dust (if any) to earned tokens
        uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
        if (token1Amt > 0 && token1Address != earnedAddress) {
            // Swap all dust tokens to earned tokens
            farmAMM.swap(
                token1Amt,
                token1ToEarnedPath,
                address(this)
            );
        }
    }

    function earn() external override whenNotPaused onlyOwner returns (uint256) {
        
        if (lastEarnBlock == block.number) return 0; // only compound once per block max
        
        // Harvest farm tokens
        _vaultHarvest();

        // Converts farm tokens into want tokens
        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));
        if (earnedAmt == 0) return 0;

        earnedAmt = buyBack(earnedAmt);

        if (earnedAddress == token0Address) {
            // Swap half earned to token1
            farmAMM.swap(
                earnedAmt / 2,
                earnedToToken1Path,
                address(this)
            );
        } else if (earnedAddress == token1Address) {
            // Swap half earned to token0
            farmAMM.swap(
                earnedAmt / 2,
                earnedToToken0Path,
                address(this)
            );
        } else {
            // Pseudorandomly pick one to swap to first. Perfect distribution and unpredictability are unnecessary, we just don't want dust collecting
            uint tokenFirst = block.timestamp % 2;
            farmAMM.swap(
            earnedAmt / 2,
            tokenFirst == 0 ? earnedToToken0Path : earnedToToken1Path,
            address(this)
            );
            //then swap the rest to the other
            farmAMM.swap(
            IERC20(earnedAddress).balanceOf(address(this)),
            tokenFirst == 0 ? earnedToToken1Path : earnedToToken0Path,
            address(this)
            );
        }

        farmAMM.add_all_liquidity(
            wantAddress,
            token0Address,
            token1Address
        );

        lastEarnBlock = block.number;

        _farm();
        
        return 0;
    }
}