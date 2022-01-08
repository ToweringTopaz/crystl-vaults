// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {ITactic, IMiniChefV2} from "./libs/Interfaces.sol";

//Polygon: 0x48D446A5571592EC101e59FEb47A0aFdD4A42566
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
    function vaultSharesTotal(address masterchefAddress, uint pid) external override view returns (uint256) {
        (uint256 amount,) = IMiniChefV2(masterchefAddress).userInfo(pid, msg.sender);
        return amount;
    }
    function _emergencyVaultWithdraw(address masterchefAddress, uint pid) external override {
        IMiniChefV2(masterchefAddress).emergencyWithdraw(pid, address(this));
    }
}