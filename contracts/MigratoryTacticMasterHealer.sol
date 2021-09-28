// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./libs/IMasterchef.sol";
import "./BaseStrategyLP.sol";
import "./MigratoryTacticBase.sol";

abstract contract MigratoryTacticMasterHealer is MigratoryTacticBase {
    
    function _vaultDeposit(address masterchefAddress, uint pid, uint256 _amount) external override {
        IMasterchef(masterchefAddress).deposit(pid, _amount);
    }
    
    function _vaultWithdraw(address masterchefAddress, uint pid, uint256 _amount) external override {
        IMasterchef(masterchefAddress).withdraw(pid, _amount);
    }
    
    function _vaultHarvest(address masterchefAddress, uint pid) external override {
        IMasterchef(masterchefAddress).withdraw(pid, 0);
    }
    
    function vaultSharesTotal(address masterchefAddress, uint pid, address _addressThis) external override view returns (uint256) {
        (uint256 amount,) = IMasterchef(masterchefAddress).userInfo(pid, _addressThis);
        return amount;
    }
    
    function _emergencyVaultWithdraw(address masterchefAddress, uint pid) external override {
        IMasterchef(masterchefAddress).emergencyWithdraw(pid);
    }
    
}