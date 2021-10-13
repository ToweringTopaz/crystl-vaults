// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./PausableTL.sol";

import "./libs/LibVaultConfig.sol";
abstract contract BaseStrategy is PausableTL {
    using LibVaultConfig for VaultSettings;
    
    VaultSettings public settings; //the major storage variables used to configure the vault
    
    uint256 public lastEarnBlock = block.number;
    
    event SetSettings(VaultSettings _settings);
    
    constructor(VaultSettings memory _settings) {
        _settings.check();
        settings = _settings;
        emit SetSettings(_settings);
    }

    modifier onlyGov virtual; //"gov"
    
    modifier whenEarnIsReady virtual { //returns without action if earn is not ready
        if (block.number >= lastEarnBlock + settings.minBlocksBetweenEarns && !paused()) {
            _;
        }
    }
    
    function earn(address _to) external virtual;
    function sharesTotal() external virtual view returns (uint256);
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
        _pause();
        _emergencyVaultWithdraw();
    }
    function unpanic() external onlyGov {
        _unpause();
        _farm();
    }
}