// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

// For interacting with our own strategy
interface IStrategy {
    // Want address
    function wantAddress() external view returns (address);
    
    // Total want tokens managed by strategy
    function wantLockedTotal() external view returns (uint256);

    // Is strategy paused
    function paused() external view returns (bool);

    // Sum of all shares of users to wantLockedTotal
    function sharesTotal() external view returns (uint256);

    // Main want token compounding function
    function earn() external;

    // Main want token compounding function
    function earn(address _to) external;

    // Transfer want tokens autoFarm -> strategy
    function deposit(address _from, address _to, uint256 _wantAmt, uint256 _sharesTotal) external returns (uint256);

    // Transfer want tokens strategy -> vaultChef
    function withdraw(address _from, address _to, uint256 _wantAmt, uint256 _userShares, uint256 _sharesTotal) external returns (uint256 sharesRemoved);
}