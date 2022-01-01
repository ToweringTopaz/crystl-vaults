// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./libs/LibVaultConfig.sol";
import "./VaultHealer.sol";

abstract contract BaseStrategy {
    using LibVaultConfig for VaultSettings;
    
    bytes32 public SETTINGS_SETTER = keccak256("SETTINGS_SETTER");

    VaultHealer immutable public vaultHealer; 
    VaultSettings public settings; //the major storage variables used to configure the vault

    event SetSettings(VaultSettings _settings);
        
    constructor(VaultSettings memory _settings, address payable _vaultHealerAddress) {
        _settings.check();
        settings = _settings;
        emit SetSettings(_settings);

        vaultHealer = VaultHealer(_vaultHealerAddress);
        settings.magnetite = VaultHealer(_vaultHealerAddress).magnetite();
    }

    //The owner of the connected vaulthealer gets administrative power in the strategy, automatically.
    modifier onlyVHRole(bytes32 role) {
        require(vaultHealer.hasRole(role, msg.sender));
        _;
    }
    modifier onlyVaultHealer {
        require(msg.sender == address(vaultHealer), "!vaulthealer");
        _;
    }

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
    
    function setSettings(VaultSettings calldata _settings) external onlyVHRole(SETTINGS_SETTER) {
        _settings.check();
        settings = _settings;
        emit SetSettings(_settings);
    }
    
    function pause() external onlyVaultHealer {
        _pause();
    }
    function unpause() external onlyVaultHealer {
        _unpause();
    }
    function panic() external onlyVaultHealer {
        _pause();
        _emergencyVaultWithdraw();
    }
    function unpanic() external onlyVaultHealer {
        _unpause();
        _farm();
    }
}