// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./libs/IStrategyCrystl.sol";
import "./libs/IUniPair.sol";
import "./libs/IUniRouter02.sol";
import "./PausableTL.sol";
import "./PathStorage.sol";
import "./VaultHealer.sol";

import "./libs/StratStructs.sol";
import "./libs/LibBaseStrategy.sol";

import "hardhat/console.sol";

abstract contract BaseStrategy is ReentrancyGuard, PausableTL, PathStorage {
    using SafeERC20 for IERC20;

    uint256 earnedLength; //number of earned tokens;
    uint256 immutable lpTokenLength; //number of underlying tokens (for a LP strategy, usually 2);
    
    Addresses public addresses; //Contains the addresses essential to vault operations
    Settings public settings; //Configuration profile
    
    uint256 public lastEarnBlock = block.number;
    uint256 public lastGainBlock; //last time earn() produced anything
    uint256 public burnedAmount; //Total CRYSTL burned by this vault
    
    //The owner of the connected vaulthealer has several privileges such as pausing the vault.
    //Cannot take user funds.
    modifier onlyGov() virtual {
        require(msg.sender == Ownable(addresses.vaulthealer).owner(), "!gov");
        _;
    }
    //VaultHealer is traditionally the contract responsible for deposits and withdrawals.
    modifier onlyVaultHealer() {
        require(msg.sender == addresses.vaulthealer, "!vaulthealer");
        _;
    }

    constructor(
        Addresses memory _addresses,
        Settings memory _settings,
        address[][] memory _paths
    ) {
        require(Ownable(_addresses.vaulthealer).owner() != address(0), "VH must have owner"); //because gov is the vaulthealer's owner
        
        _setAddresses(_addresses); //copies addresses to storage
        _setSettings(_settings); //copies settings to storage
        
        uint i;
        for (i = 0; i < _paths.length; i++) {
            _setPath(_paths[i]); //copies paths to storage
        }
        
        //The number of LP tokens and earned tokens should not be expected to change for a given pool/vault system..
        for (i = 0; i < _addresses.lpToken.length && _addresses.lpToken[i] != address(0); i++) {}
        earnedLength = i;
        for (i = 0; i < _addresses.lpToken.length && _addresses.lpToken[i] != address(0); i++) {}
        lpTokenLength = i;
    }
    
    //These are specific to a particular MasterChef/etc implementation
    function _vaultDeposit(uint256 _amount) internal virtual;
    function _vaultWithdraw(uint256 _amount) internal virtual;
    function _vaultHarvest() internal virtual;
    function vaultSharesTotal() public virtual view returns (uint256); //number of tokens currently deposited in the pool
    function _emergencyVaultWithdraw() internal virtual;
    
    //currently unused
    function _beforeDeposit(address _from, address _to) internal virtual { }
    function _beforeWithdraw(address _from, address _to) internal virtual { }
    
    //simple balance functions
    function wantBalance() internal view returns (uint256) {
        return IERC20(addresses.want).balanceOf(address(this));
    }
    
    function wantLockedTotal() public view returns (uint256) {
        return wantBalance() + vaultSharesTotal();
    }
    
    //earn() harvests and compounds earnings
    function earn() external nonReentrant { 
        _earn(_msgSender());
    }
    function earn(address _to) external nonReentrant {
        _earn(_to);
    }
    function _earn(address _to) internal virtual;
    
    //VaultHealer calls this to add funds at a user's direction. VaultHealer manages the user shares
    function deposit(address _from, address _to, uint256 _wantAmt, uint256 _sharesTotal) external onlyVaultHealer nonReentrant whenNotPaused returns (uint256 sharesAdded) {
        // Call must happen before transfer
        _beforeDeposit(_from, _to);
       
        if (_wantAmt > 0) {
            uint256 wantLockedBefore = wantLockedTotal();
            
            VaultHealer(addresses.vaulthealer).executePendingTransfer(address(this), _wantAmt);
    
            _farm();
            
            // Proper deposit amount for tokens with fees, or vaults with deposit fees
            sharesAdded = wantLockedTotal() - wantLockedBefore;
            
            if (_sharesTotal > 0) {
                sharesAdded = sharesAdded * _sharesTotal / wantLockedBefore;
            }
            require(sharesAdded >= 1, "deposit: no shares added");
        }
    }

    function withdraw(address _from, address _to, uint256 _wantAmt, uint256 _userShares, uint256 _sharesTotal) external onlyVaultHealer nonReentrant returns (uint256 sharesRemoved) {
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
        uint256 withdrawFee = Math.ceilDiv(
            _wantAmt * (WITHDRAW_FEE_FACTOR_MAX - settings.withdrawFeeFactor),
            WITHDRAW_FEE_FACTOR_MAX
        );
        _wantAmt -= withdrawFee;
        require(_wantAmt > 0, "Too small - nothing gained");
        IERC20(addresses.want).safeTransfer(addresses.withdrawFee, withdrawFee);

        IERC20(addresses.want).safeTransfer(_to, _wantAmt);
        
        return sharesRemoved;
    }

    function _farm() internal returns (uint256) {
        uint256 wantAmt = wantBalance();
        if (wantAmt == 0) return 0;
        
        uint256 sharesBefore = vaultSharesTotal();
        _allowVaultDeposit(wantAmt); //token allowance for the pool to pull the correct amount of funds only
        _vaultDeposit(wantAmt); //calls the pool contract to deposit
        uint256 sharesAfter = vaultSharesTotal();
        
        require(sharesAfter + wantBalance() >= sharesBefore + wantAmt * settings.slippageFactor / 10000,
            "High vault deposit slippage"); //safety check, will fail if there's a deposit fee rugpull
        return sharesAfter - sharesBefore;
    }

    function distributeFees(address _earnedAddress, uint256 _earnedAmt, address _to) internal returns (uint256) {
        //Moving some logic to a library reduces code size, which is limited by the EVM
        return LibBaseStrategy.distributeFees(settings, addresses, _earnedAddress, _earnedAmt, _to);
    }

    function _safeSwap(
        uint256 _amountIn,
        address _tokenA,
        address _tokenB,
        address _to
    ) internal {
        console.log("_safeSwap: amountIn: %s to: %s path: %s", _amountIn, _to, string(abi.encode(getPath(_tokenA, _tokenB))));
        //Moving some logic to a library reduces code size, which is limited by the EVM
        burnedAmount += LibBaseStrategy._safeSwap(
            settings,
            addresses,
            _amountIn,
            _tokenA,
            _tokenB,
            _to
        );
        console.log("burned: %s", burnedAmount);
    }

    function pause() external onlyGov {
        _pause();
    }
    function unpause() external onlyGov {
        _unpause();
    }
    function panic() external onlyGov {
        _pause();
        _emergencyVaultWithdraw();
    }
    function unpanic() external onlyGov {
        _unpause();
        _farm();
    }
    function setPath(address[] calldata _path) external onlyGov {
        _setPath(_path);
    }
    function setSettings(Settings calldata _settings) external onlyGov {
        _setSettings(_settings);
    }
    function setAddresses(Addresses calldata _addresses) external onlyGov {
        //Moving some logic to a library reduces code size, which is limited by the EVM
        LibBaseStrategy.setAddresses(addresses, _addresses);
    }
    
    //private configuration functions
    function _setSettings(Settings memory _settings) private {
        //Moving some logic to a library reduces code size, which is limited by the EVM
        LibBaseStrategy._setSettings(settings, _settings);
    }
    
    function _setAddresses(Addresses memory _addresses) private {
        //Moving some logic to a library reduces code size, which is limited by the EVM
        LibBaseStrategy._setAddresses(addresses, _addresses);
    }
    //to approve the masterchef immediately before a vault deposit
    function _allowVaultDeposit(uint256 _amount) private {
        IERC20(addresses.want).safeIncreaseAllowance(addresses.masterchef, _amount);
    }
    //deprecated; for front-end
    function buyBackRate() external view returns (uint) { return settings.buybackRate; }
    function tolerance() external view returns (uint) { return settings.tolerance; }
    function vaultChefAddress() external view returns (address) { return addresses.vaulthealer; }
    function setGov(address) external pure {
        revert("Gov is the vaulthealer's owner");
    }
    //required by vaulthealer
    function wantAddress() external view returns (address) { return addresses.want; }
}