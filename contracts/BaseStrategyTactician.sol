// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Address.sol";

import "./libs/ITactic.sol";

import "./BaseStrategy.sol";

interface IMasterchef {
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function emergencyWithdraw(uint256 _pid) external;
    function userInfo(uint256 _pid, address _address) external view returns (uint256, uint256);
    function harvest(uint256 _pid, address _to) external;
}

//Delegates to simple "tactic" contracts in order to interact with almost any pool or farm
abstract contract BaseStrategyTactician is BaseStrategy {
    using Address for address;
    
    address public masterchefAddress;
    ITactic public tactic;
    uint public pid;
    
    constructor(
        LibBaseStrategy.SettingsInput memory _settingsIn
    ) {
        masterchefAddress = _settingsIn.masterchefaddress;
        tactic = ITactic(_settingsIn.tactic);
        pid = _settingsIn.pid;
    }
    
    function _vaultDeposit(uint256 _amount) internal override {
        
        //token allowance for the pool to pull the correct amount of funds only
        _approveWant(masterchefAddress, _amount);
        
        address(tactic).functionDelegateCall(abi.encodeWithSelector(
            tactic._vaultDeposit.selector, masterchefAddress, pid, _amount
        ), "vaultdeposit failed");
    }
    
    function _vaultWithdraw(uint256 _amount) internal override {
        address(tactic).functionDelegateCall(abi.encodeWithSelector(
            tactic._vaultWithdraw.selector, masterchefAddress, pid, _amount
        ), "vaultwithdraw failed");
    }
    
    function _vaultHarvest() internal override {
        address(tactic).functionDelegateCall(abi.encodeWithSelector(
            tactic._vaultHarvest.selector, masterchefAddress, pid
        ), "vaultharvest failed");
    }
    
    function vaultSharesTotal() public override view returns (uint256) {
        return tactic.vaultSharesTotal(masterchefAddress, pid, address(this));
    }
    
    function _emergencyVaultWithdraw() internal override {
        address(tactic).functionDelegateCall(abi.encodeWithSelector(
            tactic._emergencyVaultWithdraw.selector, masterchefAddress, pid
        ), "emergencyvaultwithdraw failed");
    }
    
}