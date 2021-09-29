// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./libs/IMasterchef.sol";
import "./BaseStrategyLP.sol";

abstract contract MigratoryTacticBase {
    
    function _vaultDeposit(address masterchefAddress, uint pid, uint256 _amount) external virtual;
    function _vaultWithdraw(address masterchefAddress, uint pid, uint256 _amount) external virtual;
    function _vaultHarvest(address masterchefAddress, uint pid) external virtual;
    function vaultSharesTotal(address masterchefAddress, uint pid, address _addressThis) external virtual view returns (uint256);
    function _emergencyVaultWithdraw(address masterchefAddress, uint pid) external virtual;
    
}