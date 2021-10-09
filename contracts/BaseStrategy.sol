// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./PausableTL.sol";
import "./libs/LibBaseStrategy.sol";
import "./libs/LibVaultHealer.sol";
abstract contract BaseStrategy is PausableTL {
    
    LibBaseStrategy.Settings public settings; //the major storage variables used to configure the vault
    
    uint256 public lastEarnBlock = block.number;
    
    //Some routers such as dfyn use a non-standard WNATIVE token. We can get it from the router usually, or use the default (LibStrategy)
    address internal WNATIVE;
    
    modifier onlyEarner virtual { _; } //overridden to restrict "earn"
    modifier onlyGov virtual; //"gov"
    
    modifier whenEarnIsReady virtual { //returns without action if earn is not ready
        if (block.number >= lastEarnBlock + settings.minBlocksBetweenEarns && !paused()) {
            _;
        }
    }
    modifier onlyThisContract { //external call by this contract only
        require(msg.sender == address(this));
        _;
    }
    
    function _vaultDeposit(uint256 _amount) internal virtual;
    function _vaultWithdraw(uint256 _amount) internal virtual;
    function _vaultHarvest() internal virtual;
    function earn(address _to) external virtual;
    
    function sharesTotal() external virtual view returns (uint256);
    function vaultSharesTotal() public virtual view returns (uint256);
    function _wantBalance() internal virtual view returns (uint256);

    function wantLockedTotal() public view returns (uint256) {
        return _wantBalance() + vaultSharesTotal();
    }

    function _approveWant(address _to, uint256 _amount) internal virtual;
    
    function _emergencyVaultWithdraw() internal virtual;
    function _farm() internal virtual;
    
    constructor(LibBaseStrategy.SettingsInput memory _settings) {
        LibBaseStrategy.setSettings(settings, _settings);
    }
    
    //for front-end
    function buyBackRate() external view returns (uint) { 
        return settings.buybackRate;
    }
    function tolerance() external view returns (uint) {
        return settings.tolerance;
    }
    
    function setSettings(LibBaseStrategy.SettingsInput memory _settings) external onlyGov {
        LibBaseStrategy.setSettings(settings, _settings);
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