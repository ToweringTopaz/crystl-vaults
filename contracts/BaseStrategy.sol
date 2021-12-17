// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./libs/LibVaultConfig.sol";
abstract contract BaseStrategy {
    using LibVaultConfig for VaultSettings;
    
    VaultSettings public settings; //the major storage variables used to configure the vault
    
    function uniRouterAddress() external view returns (address) {
        return address(settings.router);
    }

    uint64 constant PANIC_LOCK_DURATION = 6 hours;
    uint64 public panicLockExpiry; //panic can only happen again after the time has elapsed
    uint64 public lastEarnBlock = uint64(block.number);

    event SetSettings(VaultSettings _settings);
    
    constructor(VaultSettings memory _settings) {
        _settings.check();
        settings = _settings;
        emit SetSettings(_settings);
    }

    modifier onlyGov virtual; //"gov"
    function paused() internal virtual view returns (bool);
    function vaultSharesTotal() public virtual view returns (uint256);
    function _vaultDeposit(uint256 _amount) internal virtual;
    function _vaultWithdraw(uint256 _amount) internal virtual;
    function _vaultHarvest() internal virtual;
    function _emergencyVaultWithdraw() internal virtual;
    function _farm() internal virtual;
    function _wantBalance() internal virtual view returns (uint256);
    
    function wantLockedTotal() public view returns (uint256) {
        return _wantBalance() + vaultSharesTotal();
    }

    function setSettings(VaultSettings calldata _settings) external onlyGov {
        _settings.check();
        settings = _settings;
        emit SetSettings(_settings);
    }

    function panic() external onlyGov {
        require (panicLockExpiry < block.timestamp, "panic once per 6 hours");
        _emergencyVaultWithdraw();
    }
    function unpanic() external onlyGov {
        _farm();
    }
}