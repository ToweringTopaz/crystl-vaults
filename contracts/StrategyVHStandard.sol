// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./BaseStrategyVaultHealer.sol";
import "./libs/ITactic.sol";

//This is a strategy contract which can be expected to support 99% of pools. Tactic contracts provide the pool interface.
contract StrategyVHStandard is BaseStrategyVaultHealer {
    using Address for address;
    using SafeERC20 for IERC20;
    
    address public immutable masterchef;
    ITactic public immutable tactic;
    // uint public immutable pid;

    constructor(
        IERC20 _wantToken,
        address _vaultHealerAddress,
        address _masterchefAddress,
        address _tacticAddress,
        uint256 _pid,
        VaultSettings memory _settings,
        IERC20[] memory _earned
    )
        BaseStrategy(_settings)
        BaseStrategySwapLogic(_wantToken, _earned)
        BaseStrategyVaultHealer(_vaultHealerAddress, _pid)
    {
        masterchef = _masterchefAddress;
        tactic = ITactic(_tacticAddress);
        // pid = _pid;
    }
    
    function vaultSharesTotal() public override view returns (uint256) {
        return tactic.vaultSharesTotal(masterchef, pid);
    }
    
    function _vaultDeposit(uint256 _amount) internal override {
        
        //token allowance for the pool to pull the correct amount of funds only
        wantToken.safeIncreaseAllowance(masterchef, _amount);
        
        address(tactic).functionDelegateCall(abi.encodeWithSelector(
            tactic._vaultDeposit.selector, masterchef, pid, _amount
        ), "vaultdeposit failed");
    }
    
    function _vaultWithdraw(uint256 _amount) internal override {
        address(tactic).functionDelegateCall(abi.encodeWithSelector(
            tactic._vaultWithdraw.selector, masterchef, pid, _amount
        ), "vaultwithdraw failed");
    }
    
    function _vaultHarvest() internal override {
        address(tactic).functionDelegateCall(abi.encodeWithSelector(
            tactic._vaultHarvest.selector, masterchef, pid
        ), "vaultharvest failed");
    }
    
    function _emergencyVaultWithdraw() internal override {
        address(tactic).functionDelegateCall(abi.encodeWithSelector(
            tactic._emergencyVaultWithdraw.selector, masterchef, pid
        ), "emergencyvaultwithdraw failed");
    }
        
}