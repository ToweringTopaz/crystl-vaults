// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./libs/ITactic.sol";
import "./libs/IMiniChefV2.sol";

contract TacticMiniApe is ITactic {
    
    function _vaultDeposit(address masterchefAddress, uint pid, uint256 _amount) external override {
        IMiniChefV2(masterchefAddress).deposit(pid, _amount, address(this));
    }
    
    function _vaultWithdraw(address masterchefAddress, uint pid, uint256 _amount) external override {
        IMiniChefV2(masterchefAddress).withdraw(pid, _amount, address(this));
    }
    
    function _vaultHarvest(address masterchefAddress, uint pid) external override {
        IMiniChefV2(masterchefAddress).harvest(pid, address(this));
    }
    
    function vaultSharesTotal(address masterchefAddress, uint pid, address strategyAddress) external override view returns (uint256) {
        (uint256 amount,) = IMiniChefV2(masterchefAddress).userInfo(pid, strategyAddress);
        return amount;
    }

    function _emergencyVaultWithdraw(address masterchefAddress, uint pid) external override {
        IMiniChefV2(masterchefAddress).emergencyWithdraw(pid, address(this));
    }

    
}