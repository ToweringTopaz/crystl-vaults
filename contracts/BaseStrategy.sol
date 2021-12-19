// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./libs/LibVaultConfig.sol";
import "./libs/IStrategy.sol";

abstract contract BaseStrategy {
    using LibVaultConfig for VaultSettings;
    
    VaultSettings public settings; //the major storage variables used to configure the vault
    
    uint constant PANIC_LOCK_DURATION = 6 hours;
    uint64 public panicLockExpiry; //panic can only happen again after the time has elapsed
    uint64 public lastEarnBlock = uint64(block.number);

    event SetSettings(VaultSettings _settings);
    
    constructor(VaultSettings memory _settings) {
        _settings.check();
        settings = _settings;
        emit SetSettings(_settings);
    }

    modifier onlyGov virtual; //"gov"

    function vaultSharesTotal() public virtual view returns (uint256);
    function _vaultDeposit(uint256 _amount) internal virtual;
    function _vaultWithdraw(uint256 _amount) internal virtual;
    function _vaultHarvest() internal virtual;
    function _emergencyVaultWithdraw() internal virtual;
    function _farm() internal virtual;
    function _wantBalance() internal virtual view returns (uint256);

    //support VH-based pause or standard openzeppelin method
    function _pause() internal virtual;
    function _unpause() internal virtual;
    function paused() external virtual returns (bool) {
        return false;
    }
    
    function wantLockedTotal() public view returns (uint256) {
        return _wantBalance() + vaultSharesTotal();
    }
    
    //for front-end
    function tolerance() external view returns (uint) {
        return settings.tolerance;
    }
    
    function setSettings(VaultSettings calldata _settings) external onlyGov {
        _settings.check();
        settings = _settings;
        emit SetSettings(_settings);
    }
    
    function pause() external onlyGov {
        _pause();
    }
    function unpause() external onlyGov {
        _unpause();
    }
    function panic() external onlyGov {
        require (panicLockExpiry < block.timestamp, "panic once per 6 hours");
        _pause();
        _emergencyVaultWithdraw();
    }
    function unpanic() external onlyGov {
        _unpause();
        _farm();
    }
}