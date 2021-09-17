// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

interface IMasterchef {
    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function leaveStaking(uint256 _amount) external;

    function enterStaking(uint256 _amount) external;

    function emergencyWithdraw(uint256 _pid) external;
    
    function userInfo(uint256 _pid, address _address) external view returns (uint256, uint256);
    
    function harvest(uint256 _pid, address _to) external;
}