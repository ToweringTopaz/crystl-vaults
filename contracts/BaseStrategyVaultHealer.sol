// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {IStrategy, IVaultHealer} from "./libs/Interfaces.sol";
import "./BaseStrategySwapLogic.sol";


//Deposit and withdraw for a secure VaultHealer-based system. VaultHealer is responsible for tracking user shares.
abstract contract BaseStrategyVaultHealer is BaseStrategySwapLogic {
    
    //Earn should be called with the vaulthealer, which has nonReentrant checks on deposit, withdraw, and earn.
    function earn(Vault.Fees calldata earnFees) external returns (bool success) {
        return _earn(earnFees);    
    }

    //VaultHealer calls this to add funds at a user's direction. VaultHealer manages the user shares
    function deposit(uint256 _wantAmt, uint256 _sharesTotal) external returns (uint256 sharesAdded) {
        // _earn(_from); //earn before deposit prevents abuse
        uint wantBal = _wantBalance(); ///todo: why would there be want sitting in the strat contract?
        uint wantLockedBefore = wantBal + vaultSharesTotal(); //todo: why is this different to deposit function????????????

        if (_wantAmt < settings.dust) return 0; //do nothing if nothing is requested

        //Before calling deposit here, the vaulthealer records how much the user deposits. Then with this
        //call, the strategy tells the vaulthealer to proceed with the transfer. This minimizes risk of
        //a rogue strategy 
        IVaultHealer(msg.sender).executePendingDeposit(address(this), _wantAmt);
        _farm(); //deposits the tokens in the pool
        // Proper deposit amount for tokens with fees, or vaults with deposit fees
        sharesAdded = wantLockedTotal() - wantLockedBefore;
        if (_sharesTotal > 0) { //mulDiv prevents overflow for certain tokens/amounts
            sharesAdded = HardMath.mulDiv(sharesAdded, _sharesTotal, wantLockedBefore);
        }
        require(sharesAdded > settings.dust, "deposit: no/dust shares added");
    }

    //Correct logic to withdraw funds, based on share amounts provided by VaultHealer
    function withdraw(uint _wantAmt, uint _userShares, uint _sharesTotal) external returns (uint sharesRemoved, uint wantAmt) {
        //User's balance, in want tokens
        uint wantBal = _wantBalance(); ///todo: why would there be want sitting in the strat contract?
        uint wantLockedBefore = wantBal + vaultSharesTotal(); //todo: why is this different to deposit function????????????
        uint256 userWant = HardMath.mulDiv(_userShares, wantLockedBefore, _sharesTotal);
        console.log("_wantAmt: ", _wantAmt);
        console.log("_userShares: ", _userShares);
        console.log("_sharesTotal", _sharesTotal);
        console.log("wantBal: ", wantBal);
        console.log("wantLockedBefore: ", wantLockedBefore);
        console.log("userWant: ", userWant);
        
        // user requested all, very nearly all, or more than their balance, so withdraw all
        if (_wantAmt + settings.dust > userWant) {
            _wantAmt = userWant;
            console.log("_wantAmt adjusted for withdraw all conditions: ", _wantAmt);
        }
        
        // Check if strategy has tokens from panic
        if (_wantAmt > wantBal) {
            _vaultWithdraw(_wantAmt - wantBal);
            
            wantBal = _wantBalance();
            console.log("wantBal after vaultWithdraw: ", wantBal);
        }
        
        //Account for reflect, pool withdraw fee, etc; charge these to user
        uint wantLockedAfter = wantLockedTotal();
        uint withdrawSlippage = wantLockedAfter < wantLockedBefore ? wantLockedBefore - wantLockedAfter : 0;
        console.log("wantLockedAfter: ", wantLockedAfter);
        console.log("withdrawSlippage: ", withdrawSlippage);

        //Calculate shares to remove
        sharesRemoved = HardMath.mulDivRoundingUp(
            _wantAmt + withdrawSlippage,
            _sharesTotal,
            wantLockedBefore
        );
        console.log("sharesRemoved: ", sharesRemoved);

        //Get final withdrawal amount
        if (sharesRemoved > _userShares) {
            sharesRemoved = _userShares;
            console.log("sharesRemoved: ", sharesRemoved);
        }

        _wantAmt = HardMath.mulDiv(sharesRemoved, wantLockedBefore, _sharesTotal) - withdrawSlippage;
        console.log("_wantAmt: ", _wantAmt);
        if (_wantAmt > wantBal) _wantAmt = wantBal;
        console.log("_wantAmt: ", _wantAmt);
        require(_wantAmt > 0, "nothing to withdraw after slippage");
        
        return (sharesRemoved, _wantAmt);
    }

}