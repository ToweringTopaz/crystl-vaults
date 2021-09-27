// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./BaseStrategy.sol";

abstract contract BaseStrategyLP is BaseStrategy {
    using SafeERC20 for IERC20;
    
    constructor(
        Addresses memory _addresses,
        Settings memory _settings,
        address[][] memory _paths
    ) BaseStrategy(_addresses, _settings, _paths) {
        require(_paths.length == 5, "need 5 paths for this strategy");
        
        addresses.lpToken[0] = IUniPair(_addresses.want).token0();
        addresses.lpToken[1] = IUniPair(_addresses.want).token1();
    }
    
    function earn() external override nonReentrant { 
        _earn(_msgSender());
    }

    function earn(address _to) external override nonReentrant {
        _earn(_to);
    }

    function _earn(address _to) internal {
        
        //No good reason to execute _earn twice in a block
        //Vault must not _earn() while paused!
        if (block.number < lastEarnBlock + settings.minBlocksBetweenSwaps || paused()) return;
        
        // Harvest farm tokens
        _vaultHarvest();

        bool anySwapped;
        address wantAddress = addresses.want;
        
        // Converts farm tokens into want tokens
        for (uint i; i < earnedLength; i++ ) {
            address earnedAddress = addresses.earned[i];
            
            uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));
            uint dust = settings.dust;
    
            if (earnedAmt > dust) {
                earnedAmt = distributeFees(earnedAddress, earnedAmt, _to);
        
                // Swap half earned to token0, half to token1
                anySwapped = true;
                uint _lpTokenLength = lpTokenLength;
                for (uint j; j < _lpTokenLength; i++) {
                    _safeSwap(earnedAmt / _lpTokenLength, earnedAddress, addresses.lpToken[j], wantAddress);
                }
            }
        }
        if (anySwapped) {
            // Get want tokens, ie. add liquidity
            IUniPair(wantAddress).mint(address(this));
    
            lastEarnBlock = block.number;
    
            _farm();
        }
    }
}