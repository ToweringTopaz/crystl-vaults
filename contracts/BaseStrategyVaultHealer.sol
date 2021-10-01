// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./libs/IVaultHealer.sol";

import "./BaseStrategySwapLogic.sol";

//Deposit, withdraw, earn logic for a secure VaultHealer-based system. VaultHealer is responsible for tracking user shares.
abstract contract BaseStrategyVaultHealer is BaseStrategySwapLogic {
    using SafeERC20 for IERC20;
    
    uint256 public lastEarnBlock = block.number;
    uint256 public lastGainBlock; //last time earn() produced anything
    
    address immutable public vaultChefAddress;
    
    modifier onlyVaultChef() {
        require(msg.sender == vaultChefAddress, "!vaulthealer");
        _;
    }
    
    constructor(
        address _vaultChefAddress,
        address _wantAddress,
        Settings memory _settings,
        address[8] memory _earned,
        address[8] memory _lpToken,
        address[][] memory _paths
    ) BaseStrategySwapLogic(_wantAddress, _settings, _earned, _lpToken, _paths) {
        vaultChefAddress = _vaultChefAddress;
    }
    
    //These are specific to a particular MasterChef/etc implementation
    function _vaultDeposit(uint256 _amount) internal virtual override;
    function _vaultWithdraw(uint256 _amount) internal virtual;
    function _vaultHarvest() internal virtual;
    function vaultSharesTotal() public virtual override view returns (uint256); //number of tokens currently deposited in the pool
    function _emergencyVaultWithdraw() internal virtual override;
    
    //currently unused
    function _beforeDeposit(address _from, address _to) internal virtual { }
    function _beforeWithdraw(address _from, address _to) internal virtual { }
    
    //The owner of the connected vaulthealer inherits ownership of the strategy.
    //This grants several privileges such as pausing the vault. Cannot take user funds.
    function owner() public view override returns (address) {
        return IVaultHealer(vaultChefAddress).owner();
    }

    //This is the main compounding function, which should be called via the VaultHealer
    function earn(address _to) external onlyVaultChef {
        
        //No good reason to execute _earn twice in a block
        //Vault must not _earn() while paused!
        if (block.number < lastEarnBlock + settings.minBlocksBetweenSwaps || paused()) return;
        
        //Starting want balance which is not to be touched (anti-rug)
        uint wantBalanceBefore = wantBalance();
        
        // Harvest farm tokens
        _vaultHarvest();
    
        // Converts farm tokens into want tokens
        //Try/catch means we carry on even if compounding fails for some reason
        try this._swapEarnedToLP(_to, wantBalanceBefore) returns (bool success) {
            if (success) {
                lastGainBlock = block.number; //So frontend can see if a vault no longer actually gains any value
                _farm(); //deposit the want tokens so they can begin earning
            }
        } catch {}
        
        lastEarnBlock = block.number;
    }

    //VaultHealer calls this to add funds at a user's direction. VaultHealer manages the user shares
    function deposit(address _from, address _to, uint256 _wantAmt, uint256 _sharesTotal) external onlyVaultChef whenNotPaused returns (uint256 sharesAdded) {
        _beforeDeposit(_from, _to);
       
        if (_wantAmt > 0) {
            uint256 wantLockedBefore = wantLockedTotal();
            
            IVaultHealer(vaultChefAddress).executePendingTransfer(address(this), _wantAmt);
    
            _farm();
            
            // Proper deposit amount for tokens with fees, or vaults with deposit fees
            sharesAdded = wantLockedTotal() - wantLockedBefore;
            
            if (_sharesTotal > 0) {
                sharesAdded = sharesAdded * _sharesTotal / wantLockedBefore;
            }
            require(sharesAdded > 0, "deposit: no shares added");
        }
    }
    //Correct logic to withdraw funds, based on share amounts provided by VaultHealer
    function withdraw(address _from, address _to, uint256 _wantAmt, uint256 _userShares, uint256 _sharesTotal) external onlyVaultChef returns (uint256 sharesRemoved) {
        _beforeWithdraw(_from, _to);
        
        uint wantBalanceBefore = wantBalance();
        uint wantLockedBefore = wantBalanceBefore + vaultSharesTotal();

        //User's balance, in want tokens
        uint256 userWant = _userShares * wantLockedBefore / _sharesTotal;
        
        if (_wantAmt + settings.dust > userWant) { // user requested all, very nearly all, or more than their balance
            _wantAmt = userWant;
        }      
        
        // Check if strategy has tokens from panic
        if (_wantAmt > wantBalanceBefore) {
            _vaultWithdraw(_wantAmt - wantBalanceBefore);
            uint wantBal = wantBalance();
            if (_wantAmt > wantBal) _wantAmt = wantBal;
        }
        
        //Account for reflect, pool withdraw fee, etc; charge these to user
        uint wantLockedAfter = wantLockedTotal();
        uint withdrawSlippage = wantLockedAfter < wantLockedBefore ? wantLockedBefore - wantLockedAfter : 0;
        
        //Calculate shares to remove
        sharesRemoved = Math.ceilDiv(
            (_wantAmt + withdrawSlippage) * _sharesTotal,
            wantLockedBefore
        );
        
        //User removing too many shares? Security checkpoint.
        if (sharesRemoved > _userShares) sharesRemoved = _userShares;
        
        //Get final withdrawal amount
        if (sharesRemoved < _sharesTotal) { // Calculate final withdrawal amount
            _wantAmt = (sharesRemoved * wantLockedBefore / _sharesTotal) - withdrawSlippage;
        
        } else { // last depositor is withdrawing
            assert(sharesRemoved == _sharesTotal); //for testing, should never fail
            
            //clear out anything left
            uint vaultSharesRemaining = vaultSharesTotal();
            if (vaultSharesRemaining > 0) _vaultWithdraw(vaultSharesRemaining);
            if (vaultSharesTotal() > 0) _emergencyVaultWithdraw();
            
            _wantAmt = wantBalance();
        }
        
        // Withdraw fee
        _wantAmt = collectWithdrawFee(_wantAmt);
        
        require(_wantAmt > 0, "Too small - nothing gained");
        IERC20(wantAddress).safeTransfer(_to, _wantAmt);
        
        return sharesRemoved;
    }

}