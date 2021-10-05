// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./libs/FullMath.sol";
import "./libs/IVaultHealer.sol";

import "./BaseStrategySwapLogic.sol";

//Deposit and withdraw for a secure VaultHealer-based system. VaultHealer is responsible for tracking user shares.
abstract contract BaseStrategyVaultHealer is BaseStrategySwapLogic {
    
    address immutable public vaultChefAddress;
    
    constructor(address _vaultChefAddress) {
        vaultChefAddress = _vaultChefAddress;
    }
    
    function sharesTotal() external override view returns (uint) {
        return IVaultHealer(vaultChefAddress).sharesTotal(address(this));
    }
    
    //The owner of the connected vaulthealer inherits control of the strategy.
    //This grants several privileges such as pausing the vault. Cannot take user funds.
    modifier onlyGov() override {
        require(msg.sender == IVaultHealer(vaultChefAddress).owner(), "gov is vaulthealer's owner");
        _;
    }
    
    modifier onlyVaultChef {
        require(msg.sender == vaultChefAddress, "!vaulthealer");
        _;
    }
    //This is to prevent reentrancy. Earn should be called with the vaulthealer, which has nonReentrant
    //checks on deposit, withdraw, and earn.
    function earn(address _to) external onlyVaultChef {
        _earn(_to);    
    }
    
    function magnetite() public override view returns (Magnetite) {
        return Magnetite(vaultChefAddress);
    }
    
    //VaultHealer calls this to add funds at a user's direction. VaultHealer manages the user shares
    function deposit(address _from, address /*_to*/, uint256 _wantAmt, uint256 _sharesTotal) external onlyVaultChef whenNotPaused returns (uint256 sharesAdded) {
        _earn(_from); //earn before deposit prevents abuse
       
        if (_wantAmt > 0) {
            uint256 wantLockedBefore = wantLockedTotal();
            
            IVaultHealer(vaultChefAddress).executePendingDeposit(address(this), _wantAmt);
    
            _farm();
            
            // Proper deposit amount for tokens with fees, or vaults with deposit fees
            sharesAdded = wantLockedTotal() - wantLockedBefore;
            
            if (_sharesTotal > 0) {
                sharesAdded = FullMath.mulDiv(sharesAdded, _sharesTotal, wantLockedBefore);
            }
            require(sharesAdded > 0, "deposit: no shares added");
        }
    }
    //Correct logic to withdraw funds, based on share amounts provided by VaultHealer
    function withdraw(address /*_from*/, address _to, uint256 _wantAmt, uint256 _userShares, uint256 _sharesTotal) external onlyVaultChef returns (uint256 sharesRemoved) {
        
        uint wantBalanceBefore = _wantBalance();
        uint wantLockedBefore = wantBalanceBefore + vaultSharesTotal();

        //User's balance, in want tokens
        uint256 userWant = FullMath.mulDiv(_userShares, wantLockedBefore, _sharesTotal);
        
        if (_wantAmt + settings.dust > userWant) { // user requested all, very nearly all, or more than their balance
            _wantAmt = userWant;
        }      
        
        // Check if strategy has tokens from panic
        if (_wantAmt > wantBalanceBefore) {
            _vaultWithdraw(_wantAmt - wantBalanceBefore);
            uint wantBal = _wantBalance();
            if (_wantAmt > wantBal) _wantAmt = wantBal;
        }
        
        //Account for reflect, pool withdraw fee, etc; charge these to user
        uint wantLockedAfter = wantLockedTotal();
        uint withdrawSlippage = wantLockedAfter < wantLockedBefore ? wantLockedBefore - wantLockedAfter : 0;
        
        //Calculate shares to remove
        sharesRemoved = FullMath.mulDivRoundingUp(
            _wantAmt + withdrawSlippage,
            _sharesTotal,
            wantLockedBefore
        );
        
        //User removing too many shares? Security checkpoint.
        if (sharesRemoved > _userShares) sharesRemoved = _userShares;
        
        //Get final withdrawal amount
        if (sharesRemoved < _sharesTotal) { // Calculate final withdrawal amount
            _wantAmt = FullMath.mulDiv(sharesRemoved, wantLockedBefore, _sharesTotal) - withdrawSlippage;
        } else { // last depositor is withdrawing
            assert(sharesRemoved == _sharesTotal); //for testing, should never fail
            
            //clear out anything left
            uint vaultSharesRemaining = vaultSharesTotal();
            if (vaultSharesRemaining > 0) _vaultWithdraw(vaultSharesRemaining);
            if (vaultSharesTotal() > 0) _emergencyVaultWithdraw();
            
            _wantAmt = _wantBalance();
        }
        
        // Withdraw fee
        uint256 withdrawFee = FullMath.mulDivRoundingUp(
            _wantAmt,
            WITHDRAW_FEE_FACTOR_MAX - settings.withdrawFeeFactor,
            WITHDRAW_FEE_FACTOR_MAX
        );
        //if withdrawFee > 0 && receiver is 0, strategy keeps fees
        if (withdrawFee > 0 && settings.withdrawFeeReceiver != address(0))
            _transferWant(settings.withdrawFeeReceiver, withdrawFee);
        _wantAmt -= withdrawFee;
        
        require(_wantAmt > 0, "Too small - nothing gained");
        _transferWant(_to, _wantAmt);
        
        return sharesRemoved;
    }

}