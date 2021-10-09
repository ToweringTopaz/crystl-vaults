// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./VaultHealer.sol";

import "./BaseStrategySwapLogic.sol";

//Deposit and withdraw for a secure VaultHealer-based system. VaultHealer is responsible for tracking user shares.
abstract contract BaseStrategyVaultHealer is BaseStrategySwapLogic {
    
    VaultHealer immutable public vaultHealer;
    
    constructor(address _vaultHealerAddress) {
        vaultHealer = VaultHealer(_vaultHealerAddress);
    }
    
    function sharesTotal() external override view returns (int) {
        return vaultHealer.sharesTotal(address(this));
    }
    
    //The owner of the connected vaulthealer gets administrative power in the strategy, automatically.
    modifier onlyGov() override {
        require(msg.sender == vaultHealer.owner(), "!gov");
        _;
    }
    modifier onlyVaultHealer {
        require(msg.sender == address(vaultHealer), "!vaulthealer");
        _;
    }
    //This is to prevent reentrancy. Earn should be called with the vaulthealer, which has nonReentrant
    //checks on deposit, withdraw, and earn.
    function earn(address _to) external override onlyVaultHealer {
        _earn(_to);    
    }
    
    //In this particular setup, vaulthealer inherits the Magnetite contract and provides path data
    function magnetite() public override view returns (Magnetite) {
        return Magnetite(address(vaultHealer));
    }
    
    function _update() internal override returns (uint _sharesTotal) {
        vaultHealer.stratUpdate(wantLockedTotal());
    }
    
    //VaultHealer calls this to add funds at a user's direction. VaultHealer manages the user shares
    function deposit(address _from, address /*_to*/, uint256 _wantAmt) external virtual onlyVaultHealer whenNotPaused returns (int sharesAdded) {
        
        //earn before deposit prevents abuse. Also ensures that wantlockedTotal is sharesTotal
        uint256 wantLockedBefore = _earn(_from);
       
        if (_wantAmt == 0) return 0; //do nothing if nothing is requested
        
        //Before calling deposit here, the vaulthealer records how much the user deposits. Then with this
        //call, the strategy tells the vaulthealer to proceed with the transfer. This minimizes risk of
        //a rogue strategy 
        vaultHealer.executePendingDeposit(address(this), _wantAmt);

        _farm(); //deposits the tokens in the pool
        
        // Proper deposit amount for tokens with fees, or vaults with deposit fees
        sharesAdded = int(wantLockedTotal() - wantLockedBefore);
        
        require(sharesAdded > 0, "deposit: no shares added");
    }
    //Correct logic to withdraw funds, based on share amounts provided by VaultHealer
    function withdraw(address /*_from*/, address /*_to*/, uint _wantAmt, int _userShares, uint _sharesTotal) external virtual onlyVaultHealer returns (int sharesRemoved, uint wantAmt) {
        
        //User's balance, in want tokens
        uint wantBal = _wantBalance();
        uint wantLockedBefore = wantBal + vaultSharesTotal();
        uint256 userWant = FullMath.mulDiv(_userShares, wantLockedBefore, _sharesTotal);
        
        // user requested all, very nearly all, or more than their balance, so withdraw all
        if (_wantAmt + settings.dust > userWant) {
            if (_userShares == _sharesTotal) { //user is the sole shareholder withdrawing all
                //clear out anything left
                uint vaultSharesRemaining = vaultSharesTotal();
                if (vaultSharesRemaining > 0) _vaultWithdraw(vaultSharesRemaining);
                if (vaultSharesTotal() > 0) _emergencyVaultWithdraw();
                _wantAmt = _wantBalance();
                //if receiver is 0, don't leave tokens behind in abandoned vault
                if (settings.withdrawFeeReceiver != address(0))
                    _wantAmt = collectWithdrawFee(_wantAmt);
                _approveWant(address(vaultHealer), _wantAmt);
                return (_sharesTotal, _wantAmt);
            }
            _wantAmt = userWant;
        }
        
        // Check if strategy has tokens from panic
        if (_wantAmt > wantBal) {
            _vaultWithdraw(_wantAmt - wantBal);
            
            wantBal = _wantBalance();
            
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
        
        //Get final withdrawal amount
        if (sharesRemoved > _userShares) sharesRemoved = _userShares;
        _wantAmt = FullMath.mulDiv(sharesRemoved, wantLockedBefore, _sharesTotal) - withdrawSlippage;
        
        // Withdraw fee
        _wantAmt = collectWithdrawFee(_wantAmt);
        
        _approveWant(address(vaultHealer), _wantAmt);
        return (sharesRemoved, _wantAmt);
    }
    

}