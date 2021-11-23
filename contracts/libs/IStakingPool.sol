// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

interface IStakingPool {
    function pendingReward(address _user) external view returns (uint256);
    function deposit(uint256 _amount) public;
    function withdraw(uint256 _amount) public;
    function rewardBalance() public view returns (uint256);
    function depositRewards(uint256 _amount) external;
    function emergencyWithdraw() external;
}