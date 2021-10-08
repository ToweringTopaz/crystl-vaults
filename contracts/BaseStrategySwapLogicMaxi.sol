// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./BaseStrategySwapLogic.sol";

//Contains the strategy's functions related to swapping, earning, etc.
abstract contract BaseStrategySwapLogicMaxi is BaseStrategySwapLogic {
    using SafeERC20 for IERC20;

    function xTokensTotal() public virtual view returns (uint); // number of deposited tokens whose earnings are exported rather than compounded
    function _export(address earnedToken, uint amount) internal virtual; //exports earnings

    function _earn(address _to) internal override whenEarnIsReady {
        
        uint wantBalanceBefore = _wantBalance(); //Don't touch starting want balance (anti-rug)
        //Also need old want amounts to calculate correct export amounts
        uint wantLocked = wantBalanceBefore + vaultSharesTotal(); //equivalent to wantLockedTotal()
        uint cTokens = wantLocked - xTokensTotal(); //tokens whose earnings autocompound
        
        _vaultHarvest(); // Harvest farm tokens
        
        uint dust = settings.dust; //minimum number of tokens to bother trying to compound
        bool success;
        
        for (uint i; i < earnedLength; i++) { //Process each earned token, whether it's 1, 2, or 8.
            address earnedAddress = earned[i];
            
            uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));
            
            if (earnedAddress == wantAddress)
                earnedAmt -= wantBalanceBefore; //ignore pre-existing want tokens
                
            if (earnedAmt > dust) {
                success = true; //We have something worth compounding
                earnedAmt = distributeFees(earnedAddress, earnedAmt, _to); // handles all fees for this earned token

                uint cAmt = earnedAmt * cTokens / wantLocked; //tokens that will be autocompounded
                _export(earnedAddress, earnedAmt - cAmt); //export the rest
                
                // Swap half earned to token0, half to token1 (or split evenly however we must, for balancer etc)
                // Same logic works if lpTokenLength == 1 ie single-staking pools
                for (uint j; j < lpTokenLength; j++) {
                    _safeSwap(cAmt / lpTokenLength, earnedAddress, lpToken[j], address(this));
                }
            }
        }
        //lpTokenLength == 1 means single-stake, not LP
        if (success) {
            if (lpTokenLength > 1) {
                // Get want tokens, ie. add liquidity
                PrismLibrary2.optimalMint(wantAddress, lpToken[0], lpToken[1]);
            }
            _farm();
        }
        lastEarnBlock = block.number;
    }
}