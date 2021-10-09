// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

//Tactics are used to interact with a strategy's underlying farm
interface ITactic {
    
    function _vaultDeposit(address masterchefAddress, uint pid, uint256 _amount) external;
    function _vaultWithdraw(address masterchefAddress, uint pid, uint256 _amount) external;
    function _vaultHarvest(address masterchefAddress, uint pid) external;
    function vaultSharesTotal(address masterchefAddress, uint pid, address strategyAddress) external view returns (uint256);
    function _emergencyVaultWithdraw(address masterchefAddress, uint pid) external;
    
}