// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IBoostPool {
    function bonusEndBlock() external view returns (uint256);
    function STAKE_TOKEN_VID() external view returns (uint256);
    function vaultHealerActivate(uint _boostID) external;
    function joinPool(address _user, uint _amount) external;
    function harvest(address) external;
    function emergencyWithdraw(address _user) external returns (bool success);
    function notifyOnTransfer(address _from, address _to, uint _amount) external returns (uint status);
}