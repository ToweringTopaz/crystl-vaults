// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./BaseStrategySwapLogic.sol";

//Contains the strategy's functions related to swapping, earning, etc.
abstract contract BaseStrategySwapLogicMaxi is BaseStrategySwapLogic {
    using SafeERC20 for IERC20;

    function xTokensTotal() public virtual view returns (uint); // number of deposited tokens whose earnings are exported rather than compounded
    function _export(address earnedToken, uint amount) internal virtual; //exports earnings

    //External call allows us to revert atomically, separate from everything else
    function _swapEarnedToWant(address _to, uint256 _wantBal) external override onlyThisContract returns (bool success) {

        uint wantLocked = _wantBal + vaultSharesTotal(); //equivalent to wantLockedTotal()
        uint cTokens = wantLocked - xTokensTotal(); //tokens whose earnings autocompound

        for (uint i; i < earnedLength; i++) { //Process each earned token, whether it's 1, 2, or 8.
            address earnedAddress = earned[i];
            
            uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));
            if (earnedAddress == wantAddress)
                earnedAmt -= _wantBal; //ignore pre-existing want tokens
    
            if (earnedAmt > settings.dust) { //minimum number of tokens to bother trying to compound
                success = true; //We have something worth compounding
                earnedAmt = distributeFees(earnedAddress, earnedAmt, _to); // handles all fees for this earned token
                
                uint cAmt = earnedAmt * cTokens / wantLocked;
                _export(earnedAddress, earnedAmt - cAmt); //handle exports
                
                // Swap half earned to token0, half to token1 (or split evenly however we must, for balancer etc)
                // Same logic works if lpTokenLength == 1 ie single-staking pools
                for (uint j; j < lpTokenLength; i++) {
                    _safeSwap(cAmt / lpTokenLength, earnedAddress, lpToken[j], address(this));
                }
            }
        }
        require(success, "dust-earnedToLP");
        //lpTokenLength == 1 means single-stake, not LP
        if (lpTokenLength > 1) {
            // Get want tokens, ie. add liquidity
            PrismLibrary2.optimalMint(wantAddress, lpToken[0], lpToken[1]);
        }
    }
}