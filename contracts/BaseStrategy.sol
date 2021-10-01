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

import "./libs/StratStructs.sol";
import "./libs/LibBaseStrategy.sol";

import "hardhat/console.sol";

abstract contract BaseStrategy is ReentrancyGuard, PausableTL, PathStorage {
    using SafeERC20 for IERC20;

    uint256 earnedLength; //number of earned tokens;
    uint256 immutable lpTokenLength; //number of underlying tokens (for a LP strategy, usually 2);
    bool constant _DEBUG_ = true; //must be false or removed in production
    
    Addresses public addresses; //Contains the addresses essential to vault operations
    Settings public settings; //Configuration profile
    
    uint256 public lastEarnBlock = block.number;
    uint256 public lastGainBlock; //last time earn() produced anything
    uint256 public sharesTotal; //Total shares, added and removed when depositing/withdrawing
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
        
        _resetAllowances();

    }
    
    //These are specific to a particular MasterChef/etc implementation
    function _vaultDeposit(uint256 _amount) internal virtual;
    function _vaultWithdraw(uint256 _amount) internal virtual;
    function _vaultHarvest() internal virtual;
    function vaultSharesTotal() public virtual view returns (uint256); //number of tokens currently deposited in the pool
    function _emergencyVaultWithdraw() internal virtual;
    
    //currently unused
    function _beforeDeposit(address _from) internal virtual { }
    function _beforeWithdraw(address _from) internal virtual { }
    
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
    function deposit(address _userAddress, uint256 _wantAmt) external virtual onlyVaultHealer nonReentrant whenNotPaused returns (uint256) {
        // Call must happen before transfer
        _beforeDeposit(_userAddress); //Typically a noop
        uint256 wantLockedBefore = wantLockedTotal(); //Want tokens before deposit

        IERC20(addresses.want).safeTransferFrom( //pull in tokens
            msg.sender,
            address(this),
            _wantAmt
        );

        // Proper deposit amount for tokens with fees, or vaults with deposit fees
        uint256 sharesAdded = _farm(); //deposit tokens
        if (sharesTotal > 0) {
            sharesAdded = sharesAdded * sharesTotal / wantLockedBefore; //calculate shares relative to existing pool size
        }
        require(sharesAdded >= 1, "deposit: no shares added"); //safety check
        sharesTotal += sharesAdded; //track total shares

        return sharesAdded; //vaulthealer handles user share amounts
    }

    function withdraw(address _userAddress, uint256 _wantAmt) external virtual onlyVaultHealer nonReentrant returns (uint256) {
        require(_wantAmt > 0, "_wantAmt is 0");
        //Vaulthealer handles user shares and won't let the tx get this far unless the user is owed _wantAmt
        
        _beforeWithdraw(_userAddress); //Typically a noop
        uint256 wantAmt = wantBalance(); //Total tokens held in strategy, not deposited
        
        // Check if strategy has tokens from panic
        if (_wantAmt > wantAmt) {
            _vaultWithdraw(_wantAmt - wantAmt); //withdraw tokens needed to pay the user
            wantAmt = wantBalance();
            
            if (_wantAmt > wantAmt) { //in case the whole desired amount can't be withdrawn
                _wantAmt = wantAmt;
            }
        }

        //Value withdrawal in terms of shares
        //ceilDiv prevents abuse of rounding errors
        uint256 sharesRemoved = Math.ceilDiv(_wantAmt * sharesTotal, wantLockedTotal());
        if (sharesRemoved > sharesTotal) {
            sharesRemoved = sharesTotal;
        }
        require(sharesRemoved >= 1, "withdraw: no shares removed"); //safety
        sharesTotal -= sharesRemoved;
        
        // Withdraw fee
        uint256 withdrawFee = 
            _wantAmt * 
            (WITHDRAW_FEE_FACTOR_MAX - settings.withdrawFeeFactor) /
            WITHDRAW_FEE_FACTOR_MAX;
        if (withdrawFee > 0) {
            IERC20(addresses.want).safeTransfer(addresses.withdrawFee, withdrawFee);
        }
        
        _wantAmt -= withdrawFee;

        //vaulthealer passes this on to the user
        IERC20(addresses.want).safeTransfer(addresses.vaulthealer, _wantAmt);

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

    //Admin functions
    function resetAllowances() external onlyGov {
        _resetAllowances();
    }
    function pause() external onlyGov {
        _pause();
        _resetAllowances();
    }
    function unpause() external onlyGov {
        _unpause();
        _resetAllowances();
    }
    function panic() external onlyGov {
        _pause();
        _resetAllowances();
        _emergencyVaultWithdraw();
    }
    function unpanic() external onlyGov {
        _unpause();
        _resetAllowances();
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
    function _setMaxAllowance(address token, address spender) private {
        IERC20(token).safeApprove(spender, 0);
        IERC20(token).safeIncreaseAllowance(spender, type(uint256).max);
    }
    function _setZeroAllowance(address token, address spender) private {
        IERC20(token).safeApprove(spender, 0);
    }
    //minimal allowances prevent various exploits
    function _resetAllowances() private {
        _setZeroAllowance(addresses.want, addresses.masterchef); //masterchef gets allowances only as needed
        for (uint i; i < addresses.earned.length; i++) {
            if (addresses.earned[i] != address(0)) {
                //All allowances removed while paused for security. Strategy transfers withdrawals out itself,
                //so allowances aren't needed except when unpaused
                paused() ? _setZeroAllowance(addresses.earned[i], addresses.router) :
                    _setMaxAllowance(addresses.earned[i], addresses.router);
            }
        }
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