// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./libs/LibVaultConfig.sol";
import "./libs/IStrategy.sol";
import "./VaultHealer.sol";
import "./libs/ITactic.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

abstract contract BaseStrategy is Initializable {
    using LibVaultConfig for VaultSettings;
    
    bytes32 public SETTINGS_SETTER = keccak256("SETTINGS_SETTER");

    VaultHealer public vaultHealer; 
    VaultSettings public settings; //the major storage variables used to configure the vault
    IERC20 public wantToken; //The token which is deposited and earns a yield 
    IStrategy public targetVault;
    uint public targetVid;
    IERC20 public maximizerRewardToken;
    IERC20[4] public earned;
    IERC20[2] public lpToken;
    address public masterchef;
    ITactic public tactic;
    uint public pid;

    event SetSettings(VaultSettings _settings);

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
    
    function setSettings(VaultSettings calldata _settings) external {
        _settings.check();
        settings = _settings;
        emit SetSettings(_settings);
    }

    function panic() external {
        _emergencyVaultWithdraw();
    }
    function unpanic() external {
        _farm();
    }
}