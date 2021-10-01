// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./BaseStrategy.sol";
import "./libs/PrismLibrary2.sol";
import "hardhat/console.sol";

abstract contract BaseStrategyLP is BaseStrategy {
    using SafeERC20 for IERC20;

    function _earn(address _to) internal override {
        
        //No good reason to execute _earn twice in a block
        //Vault must not _earn() while paused!
        if (block.number < lastEarnBlock + settings.minBlocksBetweenSwaps || paused()) return;
        
        // Harvest farm tokens
        _vaultHarvest();
    
        // Converts farm tokens into want tokens
        //Try/catch means we carry on even if compounding fails for some reason
        try this._swapEarnedToLP(_to) returns (bool success) {
            if (success) lastGainBlock = block.number; //So frontend can see if a vault no longer actually gains any value
        } catch {}
        
        lastEarnBlock = block.number;
    }
    
    function _swapEarnedToLP(address _to) external returns (bool success) {
        require(msg.sender == address(this)); //external call by this contract only
        
        address wantAddress = addresses.want; //our liquidity pair token, which we stake and compound and greatly desire
        console.log("_swapEarnedToLP: wantAddress is %s", wantAddress); 
        for (uint i; i < earnedLength; i++ ) { //Process each earned token, whether it's 1, 2, or 8.
            address earnedAddress = addresses.earned[i];
            console.log("_swapEarnedToLP: earnedAddress is %s", earnedAddress);
            
            uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));
            uint dust = settings.dust; //minimum number of tokens to bother trying to compound
            console.log("_swapEarnedToLP: earnedAmt is %s; greater than dust? %s", earnedAmt, earnedAmt > dust);
    
            if (earnedAmt > dust) {
                success = true; //We have something worth compounding
                
                earnedAmt = distributeFees(earnedAddress, earnedAmt, _to); // handles all fees for this earned token
        
                console.log("_swapEarnedToLP: earnedAmt after fees is %s", earnedAmt);
                console.log("_swapEarnedToLP: lpTokenLength is %s", lpTokenLength);
                
                // Swap half earned to token0, half to token1 (or split evenly however we must, for balancer etc)
                for (uint j; j < lpTokenLength; i++) {
                    _safeSwap(earnedAmt / lpTokenLength, earnedAddress, addresses.lpToken[j], address(this));
                }
            }
        }
        if (success) {
            // Get want tokens, ie. add liquidity
            PrismLibrary2.optimalMint(wantAddress, addresses.lpToken[0], addresses.lpToken[1]);
            _farm(); //deposit the want tokens so they can begin earning
        }
    }
}