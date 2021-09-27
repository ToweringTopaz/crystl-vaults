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

        if (earnedAmt > EARN_DUST) {
            earnedAmt = distributeFees(earnedAmt, _to);
    
            // Swap half earned to token0
            _safeSwap(earnedAmt / 2, earnedToToken0Path, wantAddress);
    
            // Swap half earned to token1
            _safeSwap(earnedAmt / 2, earnedToToken1Path, wantAddress);

            // Get want tokens, ie. add liquidity
            IUniPair(wantAddress).mint(address(this));
    
            lastEarnBlock = block.number;
    
            _farm();
        }
    }
}