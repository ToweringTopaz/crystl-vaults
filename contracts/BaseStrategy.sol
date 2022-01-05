// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./libs/IStrategy.sol";
import "./libs/IVaultHealer.sol";
import "./libs/ITactic.sol";

abstract contract BaseStrategy is IStrategy {

    IVaultHealer immutable public vaultHealer;
    VaultConfig public config;

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
    function _farm(uint96 dust, uint16 slippageFactor) internal virtual returns (uint);
    
    function wantLockedTotal() public view returns (uint256) {
        return config.wantToken.balanceOf(address(this)) + vaultSharesTotal();
    }

    function settings() external view returns (VaultSettings memory) {
        return vaultHealer.settings();
    }

    function panic() external onlyVaultHealer {
        _emergencyVaultWithdraw();
    }
    function unpanic(uint96 dust, uint16 slippageFactor) external onlyVaultHealer {
        _farm(dust, slippageFactor);
    }
}