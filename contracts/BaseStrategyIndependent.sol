// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BaseStrategy.sol";

abstract contract BaseStrategyIndependent is BaseStrategy, Ownable {
    using SafeERC20 for IERC20;
    
    // Info of each user.
    struct UserInfo {
        uint256 shares; // How many LP tokens the user has provided.
    }
    
    mapping (address => UserInfo) public userInfo;
    
    modifier onlyGov() override {
        require(msg.sender == owner(), "!gov");
        _;
    }
    
    //currently unused
    function _beforeDeposit(address _from, address _to) internal virtual { }
    function _beforeWithdraw(address _from, address _to) internal virtual { }
    
    function deposit(address _to, uint256 _wantAmt) external override returns (uint256 sharesAdded) {
        if (msg.sender == addresses.vaulthealer) {
            return _deposit(msg.sender, msg.sender, _wantAmt);
        }
        return _deposit(msg.sender, _to, _wantAmt);
    }
    function deposit(uint256 _wantAmt) external returns (uint256 sharesAdded) {
        return _deposit(msg.sender, msg.sender, _wantAmt);
    }
    
    function _deposit(address _from, address _to, uint256 _wantAmt) internal nonReentrant whenNotPaused returns (uint256 sharesAdded) {
        // Call must happen before transfer
        _beforeDeposit(_from, _to);
       
        if (_wantAmt > 0) {
            uint256 wantLockedBefore = wantLockedTotal();
            UserInfo storage user = userInfo[_to];
            
            IERC20(addresses.want).safeTransferFrom(
                _from,
                address(this),
                _wantAmt
            );
    
            _farm();
            
            // Proper deposit amount for tokens with fees, or vaults with deposit fees
            sharesAdded = wantLockedTotal() - wantLockedBefore;
            
            if (sharesTotal > 0) {
                sharesAdded = sharesAdded * sharesTotal / wantLockedBefore;
            }
            require(sharesAdded >= 1, "deposit: no shares added");
            user.shares += sharesAdded;
            sharesTotal += sharesAdded;
        }
        
    }
        //Danger: vaulthealer-based implementation has the address as from!!
    //function withdraw(address _to, uint256 _wantAmt) external override returns (uint256 sharesRemoved) {
    function withdrawTo(address _to, uint256 _wantAmt) external returns (uint256 sharesRemoved) {
        return _withdraw(msg.sender, _to, _wantAmt);
    }
    
    
    function withdraw(address _from, uint256 _wantAmt) external override returns (uint256 sharesRemoved) {
        require(msg.sender == addresses.vaulthealer || msg.sender == _from, 
            "Use withdrawTo to withdraw to a different address"
        );
        
        return _withdraw(msg.sender, msg.sender, _wantAmt);
    }
    
    function withdraw(uint256 _wantAmt) external returns (uint256 sharesRemoved) {
        return _withdraw(msg.sender, msg.sender, _wantAmt);
    }

    function _withdraw(address _from, address _to, uint256 _wantAmt) internal nonReentrant returns (uint256 sharesRemoved) {
        UserInfo storage user = userInfo[_from];
        require(user.shares > 0, "user.shares is 0");

        _beforeWithdraw(_from, _to);
        
        uint wantBalanceBefore = wantBalance();
        uint wantLockedBefore = wantBalanceBefore + vaultSharesTotal();

        //User's balance, in want tokens
        uint256 userWant = user.shares * wantLockedBefore / sharesTotal;
        
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
            (_wantAmt + withdrawSlippage) * sharesTotal,
            wantLockedBefore
        );
        
        //User removing too many shares? Security checkpoint.
        if (sharesRemoved > user.shares) sharesRemoved = user.shares;
        
        //Get final withdrawal amount
        if (sharesRemoved < sharesTotal) { // Calculate final withdrawal amount
            _wantAmt = (sharesRemoved * wantLockedBefore / sharesTotal) - withdrawSlippage;
        
        } else { // last depositor is withdrawing
            assert(sharesRemoved == sharesTotal); //for testing, should never fail
            
            //clear out anything left
            uint vaultSharesRemaining = vaultSharesTotal();
            if (vaultSharesRemaining > 0) _vaultWithdraw(vaultSharesRemaining);
            if (vaultSharesTotal() > 0) _emergencyVaultWithdraw();
            
            _wantAmt = wantBalance();
        }
        
        // Withdraw fee
        uint256 withdrawFee = Math.ceilDiv(
            _wantAmt * (WITHDRAW_FEE_FACTOR_MAX - settings.withdrawFeeFactor),
            WITHDRAW_FEE_FACTOR_MAX
        );
        _wantAmt -= withdrawFee;
        require(_wantAmt > 0, "Too small - nothing gained");
        IERC20(addresses.want).safeTransfer(addresses.withdrawFee, withdrawFee);

        sharesTotal -= sharesRemoved;
        user.shares -= sharesRemoved;

        IERC20(addresses.want).safeTransfer(_to, _wantAmt);
        
        return sharesRemoved;
    }
}