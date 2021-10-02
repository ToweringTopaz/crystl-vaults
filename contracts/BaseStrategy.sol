// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./libs/IUniRouter.sol";

import "./PausableTL.sol";

//Configuration settings, privileged gov functions, and basic function declarations
abstract contract BaseStrategy is PausableTL {
    
    struct Settings {
        address rewardFeeReceiver;
        address withdrawFeeReceiver;
        address buybackFeeReceiver;
        IUniRouter02 router;
        uint16 controllerFee;
        uint16 rewardRate;
        uint16 buybackRate;
        uint256 withdrawFeeFactor;
        uint256 slippageFactor;
        uint256 tolerance;
        bool feeOnTransfer;
        uint256 dust; //minimum raw token value considered to be worth swapping or depositing
        uint256 minBlocksBetweenEarns;
    }
    
    uint256 constant FEE_MAX_TOTAL = 10000;
    uint256 constant WITHDRAW_FEE_FACTOR_MAX = 10000;
    uint256 constant WITHDRAW_FEE_FACTOR_LL = 9900;
    uint256 constant SLIPPAGE_FACTOR_UL = 9950;
    
    Settings public settings;
    
    event SetSettings(Settings _settings);
    
    constructor(Settings memory _settings) {
        _setSettings(_settings); //copies settings to storage
    }
    
    //for front-end
    function buyBackRate() external view returns (uint) { 
        return settings.buybackRate;
    }
    function tolerance() external view returns (uint) {
        return settings.tolerance;
    }
    
    //sum of all owned want tokens in the vault
    function wantLockedTotal() public view returns (uint256) {
        return _wantBalance() + vaultSharesTotal();
    }
    //number of tokens currently deposited in the pool
    function vaultSharesTotal() public virtual view returns (uint256);
    
    //number of want tokens currently held in this contract, not deposited in pool
    function _wantBalance() internal virtual view returns (uint256);
    function _vaultDeposit(uint256 _amount) internal virtual; //to deposit tokens in the pool
    function _vaultHarvest() internal virtual; //To collect accumulated reward tokens
    function _vaultWithdraw(uint256 _amount) internal virtual;
    function _emergencyVaultWithdraw() internal virtual;
    function _farm() internal virtual;
    function sharesTotal() external virtual view returns (uint256);
    function _approveWant(address _to, uint256 _amount) internal virtual;
    function _transferWant(address _to, uint256 _amount) internal virtual;
    
    modifier onlyEarner virtual { //can be overridden to restrict the ability to call "earn"
        _;
    }
    
    function _setSettings(Settings memory _settings) private {
        require(_settings.rewardFeeReceiver != address(0), "Invalid reward address");
        require(_settings.buybackFeeReceiver != address(0), "Invalid buyback address");
        require(_settings.controllerFee + _settings.rewardRate + _settings.buybackRate <= FEE_MAX_TOTAL, "Max fee of 100%");
        require(_settings.withdrawFeeFactor >= WITHDRAW_FEE_FACTOR_LL, "_withdrawFeeFactor too low");
        require(_settings.withdrawFeeFactor <= WITHDRAW_FEE_FACTOR_MAX, "_withdrawFeeFactor too high");
        require(_settings.slippageFactor <= SLIPPAGE_FACTOR_UL, "_slippageFactor too high");
        try _settings.router.factory() returns (address) {}
        catch { revert("Invalid router"); }
        
        settings = _settings;
        
        emit SetSettings(_settings);
    }
    
    //For access to privileged functions which can impact major vault functions.
    modifier onlyGov virtual;
    
    function setSettings(Settings calldata _settings) external onlyGov {
        _setSettings(_settings);
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
    
}