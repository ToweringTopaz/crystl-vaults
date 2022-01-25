// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {IStrategy, IVaultHealer} from "./libs/Interfaces.sol";
import "./BaseStrategySwapLogic.sol";
import {MathUpgradeable as Math} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

//Deposit and withdraw for a secure VaultHealer-based system. VaultHealer is responsible for tracking user shares.
abstract contract BaseStrategyVaultHealer is BaseStrategySwapLogic {

    //VaultHealer calls this to add funds at a user's direction. VaultHealer manages the user shares
    function deposit(uint256 _wantAmt, uint256 _sharesTotal) external returns (uint256 sharesAdded) {
        // _earn(_from); //earn before deposit prevents abuse
        uint wantBal = wantToken.balanceOf(address(this)); ///todo: why would there be want sitting in the strat contract?
        uint wantLockedBefore = wantBal + vaultSharesTotal(); //todo: why is this different to deposit function????????????
        uint dust = settings.dust;

        if (_wantAmt < dust) return 0; //do nothing if nothing is requested

        //Before calling deposit here, the vaulthealer records how much the user deposits. Then with this
        //call, the strategy tells the vaulthealer to proceed with the transfer. This minimizes risk of
        //a rogue strategy 
        IVaultHealer(msg.sender).executePendingDeposit(address(this), uint112(_wantAmt));
        _farm(); //deposits the tokens in the pool
        // Proper deposit amount for tokens with fees, or vaults with deposit fees
        sharesAdded = wantLockedTotal() - wantLockedBefore;
        if (_sharesTotal > 0) { 
            sharesAdded = Math.ceilDiv(sharesAdded * _sharesTotal, wantLockedBefore);
        }
        require(sharesAdded > dust, "deposit: no/dust shares added");
    }

    //Correct logic to withdraw funds, based on share amounts provided by VaultHealer
    function withdraw(uint _wantAmt, uint _userShares, uint _sharesTotal) external returns (uint sharesRemoved, uint wantAmt) {
        //User's balance, in want tokens
        uint wantBal = wantToken.balanceOf(address(this)); ///todo: why would there be want sitting in the strat contract?
        uint wantLockedBefore = wantBal + vaultSharesTotal(); //todo: why is this different to deposit function????????????
        uint256 userWant = _userShares * wantLockedBefore / _sharesTotal;
        
        // user requested all, very nearly all, or more than their balance, so withdraw all
        uint dust = settings.dust;
        if (_wantAmt + dust > userWant) {
            _wantAmt = userWant;
        }
        
        // Check if strategy has tokens from panic
        if (_wantAmt > wantBal) {
            _vaultWithdraw(_wantAmt - wantBal);
            
            wantBal = wantToken.balanceOf(address(this));
        }

        //Account for reflect, pool withdraw fee, etc; charge these to user
        uint wantLockedAfter = wantLockedTotal();
        uint withdrawSlippage = wantLockedAfter < wantLockedBefore ? wantLockedBefore - wantLockedAfter : 0;

        //Calculate shares to remove
        sharesRemoved = Math.ceilDiv(
            (_wantAmt + withdrawSlippage) * _sharesTotal,
            wantLockedBefore
        );

        //Get final withdrawal amount
        if (sharesRemoved > _userShares) {
            sharesRemoved = _userShares;
        }

        _wantAmt = Math.ceilDiv(sharesRemoved * wantLockedBefore, _sharesTotal) - withdrawSlippage;
        if (_wantAmt > wantBal) _wantAmt = wantBal;

        require(_wantAmt > 0, "nothing to withdraw after slippage");
        
        return (sharesRemoved, _wantAmt);
    }

}