// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import"./libs/IVaultHealer.sol";
import "./BaseStrategySwapLogic.sol";

//Deposit and withdraw for a secure VaultHealer-based system. VaultHealer is responsible for tracking user shares.
abstract contract BaseStrategyVaultHealer is BaseStrategySwapLogic {
    using SafeERC20 for IERC20;

    //VaultHealer calls this to add funds at a user's direction. VaultHealer manages the user shares
    function deposit(uint256 _wantAmt) external onlyVaultHealer returns (uint256 tokensAdded) {
        uint96 dust = settings.dust;
        if (_wantAmt < dust) return 0; //do nothing if nothing is requested

        //todo: why would there be want sitting in the strat contract? - because nothing stops users from transferring in tokens, often flashloaned!
        uint wantLockedBefore = wantLockedTotal(); //todo: why is this different to deposit function???????????? - wantLockedTotal is defined as want balance+ vaultSharesTotal. Sometimes we need the two separately, sometimes we don't

        //Before calling deposit here, the vaulthealer records how much the user deposits. Then with this
        //call, the strategy tells the vaulthealer to proceed with the transfer. This minimizes risk of
        //a rogue strategy 
        vaultHealer.executePendingDeposit(address(this), _wantAmt);

        uint wantLockedAfter = _farm(); //deposits the tokens in the pool

        tokensAdded = wantLockedAfter - wantLockedBefore; // Proper deposit amount for tokens with fees, or vaults with deposit fees
        if (tokensAdded > _wantAmt) tokensAdded = _wantAmt; //no credit for excess, improperly added tokens - exploit safety

        require(tokensAdded > settings.dust, "deposit: no/dust shares added");
    }
    error WithdrawSlippagePanicError(uint vaultWithdrawAmt, uint wantLockedBefore, uint wantBal, uint slippageFactor);    

    //Correct logic to withdraw funds, based on share amounts provided by VaultHealer
    function withdraw(uint _wantAmt, uint _wantAvailable) external onlyVaultHealer returns (uint tokensRemoved, uint wantAmt) {
        //User's balance, in want tokens
        IERC20 wantToken = config.wantToken;
        uint wantBal = wantToken.balanceOf(address(this));
        uint wantLockedBefore = vaultSharesTotal() + wantBal;
        uint dust = settings.dust;

        // user requested all, very nearly all, or more than their balance, so withdraw all
        wantAmt = _wantAmt + dust > _wantAvailable ? _wantAvailable : _wantAmt;

        //amount we need to withdraw from the pool. Don't try if we're in a panic
        uint vaultWithdrawAmt = (status != VaultStatus.PANIC) && (wantAmt > wantBal)
            ? wantAmt - wantBal
            : 0;

        if (vaultWithdrawAmt > 0) {
            _vaultWithdraw(wantAmt - wantBal);
            wantBal = wantToken.balanceOf(address(this));
            //Account for reflect, pool withdraw fee, etc; charge these to user
            uint wantLockedAfter = wantLockedTotal();
            
            if (wantLockedAfter < wantLockedBefore) tokensRemoved = wantLockedBefore - wantLockedAfter;

            //if slippage is too high, the vault should autopanic
            unchecked{
                if (tokensRemoved > 0) {
                    uint slippageFactor = settings.slippageFactorWithdraw;
                    if (tokensRemoved > (10000 - slippageFactor) * vaultWithdrawAmt / 10000) {
                        //todo: VH try/catch
                        revert WithdrawSlippagePanicError(vaultWithdrawAmt, wantLockedBefore, wantLockedAfter, slippageFactor);
                    }
                    _wantAvailable -= tokensRemoved;
                }
            }
            if (_wantAvailable > wantBal) _wantAvailable = wantBal;
        }
        
        if (wantAmt + dust > _wantAvailable) wantAmt = _wantAvailable; //Get final withdrawal amount
        tokensRemoved += wantAmt;
        wantToken.safeIncreaseAllowance(address(vaultHealer), wantAmt);
        return (tokensRemoved, wantAmt);
    }

}