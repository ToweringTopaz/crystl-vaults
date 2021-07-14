// SPDX-License-Identifier: MIT

/*
Join us at PolyCrystal.Finance!
█▀▀█ █▀▀█ █░░ █░░█ █▀▀ █▀▀█ █░░█ █▀▀ ▀▀█▀▀ █▀▀█ █░░ 
█░░█ █░░█ █░░ █▄▄█ █░░ █▄▄▀ █▄▄█ ▀▀█ ░░█░░ █▄▄█ █░░ 
█▀▀▀ ▀▀▀▀ ▀▀▀ ▄▄▄█ ▀▀▀ ▀░▀▀ ▄▄▄█ ▀▀▀ ░░▀░░ ▀░░▀ ▀▀▀
*/

pragma solidity 0.6.12;

import "./BaseStrategyApeLP.sol";

abstract contract BaseStrategyApeLPSingle is BaseStrategyApeLP {
    using SafeERC20 for IERC20;
    
    function _vaultHarvest() internal virtual;

    function earn() external override whenNotPaused onlyOwner {
        
        if (lastEarnBlock == block.number) return; // only compound once per block max
        
        // Harvest farm tokens
        _vaultHarvest();

        // Converts farm tokens into want tokens
        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));
        if (earnedAmt == 0) return;

        earnedAmt = buyBack(earnedAmt);

        if (earnedAddress == token0Address) {
            // Swap half earned to token1
            _swap(
                earnedAmt / 2,
                earnedToToken1Path,
                address(this)
            );
        } else if (earnedAddress == token1Address) {
            // Swap half earned to token0
            _swap(
                earnedAmt / 2,
                earnedToToken0Path,
                address(this)
            );
        } else {
            // Pseudorandomly pick one to swap to first. Perfect distribution and unpredictability are unnecessary, we just don't want dust collecting
            uint tokenFirst = block.timestamp % 2;
            _swap(
            earnedAmt / 2,
            tokenFirst == 0 ? earnedToToken0Path : earnedToToken1Path,
            address(this)
            );
            //then swap the rest to the other
            _swap(
            IERC20(earnedAddress).balanceOf(address(this)),
            tokenFirst == 0 ? earnedToToken1Path : earnedToToken0Path,
            address(this)
            );
        }

        add_all_liquidity(
            wantAddress,
            token0Address,
            token1Address
        );

        lastEarnBlock = block.number;

        _farm();
    }
}
