// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./Boolean256.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStrategy {
    function wantAddress() external view returns (address); // Want address
    function wantLockedTotal() external view returns (uint256); // Total want tokens managed by strategy
    function paused() external view returns (bool); // Is strategy paused
    function earn(address _to) external; // Main want token compounding function
    function deposit(address _from, address _to, uint256 _wantAmt, uint256 _sharesTotal) external returns (uint256);
    function withdraw(address _from, address _to, uint256 _wantAmt, uint256 _userShares, uint256 _sharesTotal) external returns (uint256 sharesRemoved);
}

struct UserInfo {
    int shares; // Shares for standard auto-compound rewards
    //maximizer functions below. Ignored for standard VaultHealer
    int xTokensTotal; //Total tokens the user has earning/exporting at this pool
    bool256 allImports; // all pids from which this user/pool import shares
    bool256 allExports; // all pids to whom this user/pool export shares
    mapping(uint8 => int) xTokens; // for each pool
    bytes userData; //unused for now
}

struct PoolInfo {
    IERC20 want; // Address of the want token.
    IStrategy strat; // Strategy address that will auto compound want tokens
    uint256 sharesTotal;
    uint256 xTokensTotal;
    bool256 allImports; // all pids from which this pool import shares
    bool256 allExports; // all pids to whom this pool export shares
    mapping (uint8 => uint) xTokens; //for each pool, totals
    mapping (address => UserInfo) user;
    bytes poolData; //unused for now
}

library LibMaximizer {
    
    function balanceBasic(uint b) {
        
    }
    
    
}