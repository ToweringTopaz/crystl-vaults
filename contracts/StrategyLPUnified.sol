// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./libs/IMasterchef.sol";
import "./libs/ITactic.sol";
import "./BaseStrategyLP.sol";
import "./VaultHealer.sol";

contract StrategyLPUnified is BaseStrategyLP {
    using Address for address;
    
    uint pid;
    ITactic public immutable tactic;
    
    constructor(
        Addresses memory _addresses,
        Settings memory _settings,
        address[][] memory _paths,  //need paths for earned to each of (wmatic, dai, crystl, token0, token1): 5 total
        uint256 _pid,
        ITactic _tactic
    ) BaseStrategy(_addresses, _settings, _paths) {
        
        addresses.lpToken[0] = IUniPair(_addresses.want).token0();
        addresses.lpToken[1] = IUniPair(_addresses.want).token1();
        
        pid = _pid;
        tactic = _tactic;
    }

    function _vaultDeposit(uint256 _amount) internal virtual override {
        address(tactic).functionDelegateCall(abi.encodeWithSelector(
            tactic._vaultDeposit.selector, addresses.masterchef, pid, _amount
        ), "vaultdeposit failed");
    }
    
    function _vaultWithdraw(uint256 _amount) internal virtual override {
        address(tactic).functionDelegateCall(abi.encodeWithSelector(
            tactic._vaultWithdraw.selector, addresses.masterchef, pid, _amount
        ), "vaultwithdraw failed");
    }
    
    function _vaultHarvest() internal virtual override {
        address(tactic).functionDelegateCall(abi.encodeWithSelector(
            tactic._vaultHarvest.selector, addresses.masterchef, pid
        ), "vaultharvest failed");
    }
    
    function vaultSharesTotal() public virtual override view returns (uint256) {
        return tactic.vaultSharesTotal(addresses.masterchef, pid, address(this));
    }
    
    function _emergencyVaultWithdraw() internal virtual override {
        address(tactic).functionDelegateCall(abi.encodeWithSelector(
            tactic._emergencyVaultWithdraw.selector, addresses.masterchef, pid
        ), "emergencyvaultwithdraw failed");
    }
}