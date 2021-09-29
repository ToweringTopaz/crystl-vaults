// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./BaseStrategy.sol";
import "./libs/PrismLibrary2.sol";

abstract contract BaseStrategyLP is BaseStrategy {
    using SafeERC20 for IERC20;

    function _earn(address _to) internal override {
        
        //No good reason to execute _earn twice in a block
        //Vault must not _earn() while paused!
        if (block.number < lastEarnBlock + settings.minBlocksBetweenSwaps || paused()) return;
        
        // Harvest farm tokens
        _vaultHarvest();
        
        // Converts farm tokens into want tokens
        if (_DEBUG_) {
            this._swapEarnedToLP(_to);
        } else {
            try this._swapEarnedToLP(_to) returns (bool success) {
                if (success) lastGainBlock = block.number;
            } catch {}
        }
        
        lastEarnBlock = block.number;
    }
    
    function _swapEarnedToLP(address _to) external returns (bool success) {
        require(msg.sender == address(this)); //external call by this contract only
        
        address wantAddress = addresses.want;
        console.log("_swapEarnedToLP: wantAddress is %s", wantAddress);
        for (uint i; i < earnedLength; i++ ) {
            address earnedAddress = addresses.earned[i];
            console.log("_swapEarnedToLP: earnedAddress is %s", earnedAddress);
            if (earnedAddress == address(0)) break;
            
            uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));
            uint dust = settings.dust;
            console.log("_swapEarnedToLP: earnedAmt is %s; greater than dust? %s", earnedAmt, earnedAmt > dust);
    
            if (earnedAmt > dust) {
                earnedAmt = distributeFees(earnedAddress, earnedAmt, _to);
        
                console.log("_swapEarnedToLP: earnedAmt after fees is %s", earnedAmt);
                // Swap half earned to token0, half to token1
                success = true;
                uint _lpTokenLength = lpTokenLength;
                console.log("_swapEarnedToLP: _lpTokenLength is %s", _lpTokenLength);
                for (uint j; j < _lpTokenLength; i++) {
                    _safeSwap(earnedAmt / _lpTokenLength, earnedAddress, addresses.lpToken[j], address(this));
                }
            }
        }
        if (success) {
            // Get want tokens, ie. add liquidity
            PrismLibrary2.optimalMint(wantAddress, addresses.lpToken[0], addresses.lpToken[1]);
            _farm();
        }
    }
}