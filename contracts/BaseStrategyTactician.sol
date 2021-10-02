// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./libs/ITactic.sol";

import "./BaseStrategy.sol";

//Delegates to simple "tactic" contracts in order to interact with almost any pool or farm
abstract contract BaseStrategyTactician is BaseStrategy {
    using Address for address;
    using SafeERC20 for IERC20;
    
    address public immutable masterchefAddress;
    ITactic public immutable tactic;
    uint public immutable pid;
    
    constructor(
        address _masterchefAddress,
        address _tactic,
        uint256 _pid
    ) {
        masterchefAddress = _masterchefAddress;
        tactic = ITactic(_tactic);
        pid = _pid;
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