// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./libs/IStrategy.sol";
import "./libs/ITactic.sol";
import "./libs/Vault.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20Upgradeable as IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

abstract contract BaseStrategy is Initializable, IStrategy {

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
    
    function setSettings(Vault.Settings calldata _settings) external {
        Vault.check(_settings);
        settings = _settings;
        emit SetSettings(_settings);
    }

    function panic() external {
        _emergencyVaultWithdraw();
    }
    function unpanic() external {
        _farm();
    }
//    function router() external view returns (IUniRouter) {
//        return settings.router;
//    }
}