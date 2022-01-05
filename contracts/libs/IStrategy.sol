// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./VaultSettings.sol";

interface IStrategy {
    


    function wantToken() external view returns (IERC20); // Want address
    function panic() external;
    function unpanic() external;
    function settings() external view returns (VaultSettings memory);
    function earn(VaultSettings calldata settings) external returns (bool success, uint wantLocked);
    function compound(VaultSettings calldata settings, uint256 depositAmt, uint256 _exportSharesTotal, uint256 _sharesTotal) external payable returns (uint256 sharesAdded);
    function wantLockedTotal() external view returns (uint256); // Total want tokens managed by strategy
    /*
    function boostPoolAddress() external view returns (address);

    function accRewardTokensPerShare() external view returns (uint256);
    function increaseRewardDebt(address _user, uint256 _amount) external;
    function getRewardDebt(address _user) external view returns (uint256);
    function UpdatePoolAndWithdrawCrystlOnWithdrawal(address _from, uint256 _amount, uint256 _userWant) external;
    function UpdatePoolAndRewarddebtOnDeposit(address _to, uint256 _amount) external;
    function isMaximizer() external view returns (bool);
    function targetVault() external view returns (IStrategy);
    function maximizerRewardToken() external view returns (IERC20);
    function withdrawMaximizerReward(uint256 _pid, uint256 _amount) external;
    function earn(VaultFees calldata _fees) external returns (bool success); // Main want token compounding function
    function deposit(uint256 _wantAmt, uint256 _sharesTotal) external returns (uint256);
    function withdraw(uint256 _wantAmt, uint256 _userShares, uint256 _sharesTotal) external returns (uint256 sharesRemoved, uint256 wantAmt);

    
        // Univ2 router used by this strategy
    
    */
}