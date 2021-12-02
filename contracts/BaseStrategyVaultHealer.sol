// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./VaultHealer.sol";

import "./BaseStrategySwapLogic.sol";

//Deposit and withdraw for a secure VaultHealer-based system. VaultHealer is responsible for tracking user shares.
abstract contract BaseStrategyVaultHealer is BaseStrategySwapLogic {
    using SafeERC20 for IERC20;
    using LibVaultConfig for VaultFees;
    using LibVaultSwaps for VaultFees;    
    
    VaultHealer immutable public vaultHealer;
    address public stakingPoolAddress;
    
    constructor(address _vaultHealerAddress) {
        vaultHealer = VaultHealer(_vaultHealerAddress);
        settings.magnetite = Magnetite(_vaultHealerAddress);
    }
    
    function sharesTotal() external view returns (uint) {
        return vaultHealer.sharesTotal(address(this));
    }
    
    //The owner of the connected vaulthealer gets administrative power in the strategy, automatically.
    modifier onlyGov() override {
        require(msg.sender == vaultHealer.owner() || msg.sender == address(vaultHealer), "!gov");
        _;
    }
    modifier onlyVaultHealer {
        require(msg.sender == address(vaultHealer), "!vaulthealer");
        _;
    }
    //Earn should be called with the vaulthealer, which has nonReentrant checks on deposit, withdraw, and earn.
    function earn(address _to) external onlyVaultHealer {
        _earn(_to);    
    }

    //VaultHealer calls this to add funds at a user's direction. VaultHealer manages the user shares
    function deposit(address _from, address /*_to*/, uint256 _wantAmt, uint256 _sharesTotal) external payable onlyVaultHealer returns (uint256 sharesAdded) {
        require(_wantAmt > 0 || msg.value > 0, "Strategy: nothing to deposit");
        _earn(_from); //earn before deposit prevents abuse

        uint256 wantLockedBefore = wantLockedTotal();

        if (msg.value > 0) { //convert all msg.value eth to want tokens
            for (uint i; i < lpTokenLength; i++) {
                LibVaultSwaps.safeSwapETH(settings, msg.value / lpTokenLength, lpToken[i], address(this));
            }
            if (lpTokenLength > 1) {
                // Get want tokens, ie. add liquidity
                LibVaultSwaps.optimalMint(wantToken, lpToken[0], lpToken[1]);
            }
        }
        
        //Before calling deposit here, the vaulthealer records how much the user deposits. Then with this
        //call, the strategy tells the vaulthealer to proceed with the transfer. This minimizes risk of
        //a rogue strategy 
        if (_wantAmt > 0) vaultHealer.executePendingDeposit(address(this), _wantAmt);

        _farm(); //deposits the tokens in the pool
        
        // Proper deposit amount for tokens with fees, or vaults with deposit fees
        sharesAdded = wantLockedTotal() - wantLockedBefore;
        
        if (_sharesTotal > 0) { //mulDiv prevents overflow for certain tokens/amounts
            sharesAdded = FullMath.mulDiv(sharesAdded, _sharesTotal, wantLockedBefore);
        }
        require(sharesAdded > settings.dust, "deposit: no/dust shares added");
    }
    //Correct logic to withdraw funds, based on share amounts provided by VaultHealer
    function withdraw(address /*_from*/, address /*_to*/, uint _wantAmt, uint _userShares, uint _sharesTotal) external onlyVaultHealer returns (uint sharesRemoved, uint wantAmt) {
        
        //User's balance, in want tokens
        uint wantBal = _wantBalance();
        uint wantLockedBefore = wantBal + vaultSharesTotal();
        uint256 userWant = FullMath.mulDiv(_userShares, wantLockedBefore, _sharesTotal) ;
        
        // user requested all, very nearly all, or more than their balance, so withdraw all
        if (_wantAmt + settings.dust > userWant)
            _wantAmt = userWant;
        
        // Check if strategy has tokens from panic
        if (_wantAmt > wantBal) {
            _vaultWithdraw(_wantAmt - wantBal);
            
            wantBal = _wantBalance();
            
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
        
        if (_wantAmt > wantBal) _wantAmt = wantBal;
        require(_wantAmt > 0, "nothing to withdraw after slippage");
        
        wantToken.safeIncreaseAllowance(address(vaultHealer), _wantAmt);
        return (sharesRemoved, _wantAmt);
    }
    
    function _pause() internal override {} //no-op, since vaulthealer manages paused status
    function _unpause() internal override {}
    function paused() public view override returns (bool) {
        return vaultHealer.paused(address(this));
    }

    function setStakingPoolAddress(address _stakingPoolAddress) external {
        stakingPoolAddress = _stakingPoolAddress;
    }
}