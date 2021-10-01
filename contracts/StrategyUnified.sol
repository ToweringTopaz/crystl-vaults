// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./libs/ITactic.sol";

import "./BaseStrategyVaultHealer.sol";

//This is a strategy contract which can be expected to support 99% of pools. Tactic contracts provide the pool interface.
contract StrategyUnified is BaseStrategyVaultHealer {
    using Address for address;
    using SafeERC20 for IERC20;
    
    uint public immutable pid;
    address public immutable masterchefAddress;
    ITactic public immutable tactic;
    
    constructor(
        address _masterchefAddress,
        address _tactic,
        uint256 _pid,
        address _vaultChefAddress,
        address _wantAddress,
        Settings memory _settings,
        address[] memory _earned,
        address[][] memory _paths
    ) BaseStrategyVaultHealer(
        _vaultChefAddress, 
        _wantAddress, 
        _settings, 
        _earned,
        [address(0),address(0)], //LP tokens are auto-filled
        _paths
    ){
        
        masterchefAddress = _masterchefAddress;
        tactic = ITactic(_tactic);
        pid = _pid;
    }

    function _vaultDeposit(uint256 _amount) internal override {
        
        //token allowance for the pool to pull the correct amount of funds only
        IERC20(wantAddress).safeIncreaseAllowance(masterchefAddress, _amount);
        
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