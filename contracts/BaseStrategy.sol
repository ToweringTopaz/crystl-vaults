// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./libs/IStrategy.sol";
import "./libs/IVaultHealer.sol";
import "./libs/ITactic.sol";

abstract contract BaseStrategy is IStrategy {

    IVaultHealer immutable public vaultHealer;
    VaultConfig config; //configuration data which is immutable
    VaultSettings settings; //
    VaultStatus status;

    constructor(address payable _vaultHealerAddress) {
        vaultHealer = IVaultHealer(_vaultHealerAddress);
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
    function _farm() internal virtual returns (uint);
    
    function wantLockedTotal() public view returns (uint256) {
        return config.wantToken.balanceOf(address(this)) + vaultSharesTotal();
    }

    function setSettings(VaultSettings calldata _settings) external onlyVaultHealer {
        settings = _settings;
    }

    function panic() external onlyVaultHealer {
        status = VaultStatus.PANIC;
        _emergencyVaultWithdraw();
    }
    function unpanic() external onlyVaultHealer {
        status = VaultStatus.NORMAL;
        _farm();
    }
}