// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./BaseStrategy.sol";

abstract contract BaseStrategyLPSingle is BaseStrategy {
    using SafeERC20 for IERC20;
    
    address public token0Address;
    address public token1Address;

    address[] public earnedToToken0Path;
    address[] public earnedToToken1Path;
    
    function earn() external override nonReentrant { 
        _earn(_msgSender());
    }

    function earn(address _to) external override nonReentrant {
        _earn(_to);
    }

    function _earn(address _to) internal {
        
        //No good reason to execute _earn twice in a block
        //Vault must not _earn() while paused!
        if (block.number == lastEarnBlock || paused()) return;
        
        // Harvest farm tokens
        _vaultHarvest();

        // Converts farm tokens into want tokens
        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

        if (earnedAmt > 0) {
            earnedAmt = distributeFees(earnedAmt, _to);
    
            if (earnedAddress != token0Address) {
                // Swap half earned to token0
                _safeSwap(
                    earnedAmt / 2,
                    earnedToToken0Path,
                    address(this)
                );
            }
    
            if (earnedAddress != token1Address) {
                // Swap half earned to token1
                _safeSwap(
                    earnedAmt / 2,
                    earnedToToken1Path,
                    address(this)
                );
            }
    
            // Get want tokens, ie. add liquidity
            uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
            uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
            if (token0Amt > 0 && token1Amt > 0) {
                IUniRouter02(uniRouterAddress).addLiquidity(
                    token0Address,
                    token1Address,
                    token0Amt,
                    token1Amt,
                    0,
                    0,
                    address(this),
                    block.timestamp + 600
                );
            }
    
            lastEarnBlock = block.number;
    
            _farm();
        }
    }
}