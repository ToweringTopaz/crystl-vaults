// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

interface IBoostPool {
    function pendingReward(address _user) external view returns (uint256);
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _amount, address _user) external;
    function rewardBalance() external view returns (uint256);
    function depositRewards(uint256 _amount) external;
    function emergencyWithdraw(address _user) external returns (bool);
    function userStakedAmount(address _user) external view returns (uint256);
    function vaultHealerActivate(uint _boostID) external;
    function bonusEndBlock() external view returns (uint256);
    function STAKE_TOKEN_PID() external view returns (uint256);
    function joinPool(address _user, uint _amount) external;
    function notifyOnTransfer(address _from, address _to, uint _amount) external returns (uint status);
}