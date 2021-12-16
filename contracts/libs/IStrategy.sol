// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./LibVaultConfig.sol";

interface IStrategy {
    function wantToken() external view returns (IERC20); // Want address
    function boostPoolAddress() external view returns (address);
    function wantLockedTotal() external view returns (uint256); // Total want tokens managed by strategy
    function accRewardTokensPerShare() external view returns (uint256);
    function increaseRewardDebt(address _user, uint256 _amount) external;
    function getRewardDebt(address _user) external view returns (uint256);
    function UpdatePoolAndWithdrawCrystlOnWithdrawal(address _from, uint256 _amount, uint256 _userWant) external;
    function UpdatePoolAndRewarddebtOnDeposit(address _to, uint256 _amount) external;
    function CheckIsMaximizer() external view returns (bool);
    function maximizerVault() external view returns (IStrategy);
    function maximizerRewardToken() external view returns (IERC20);
    function withdrawMaximizerReward(uint256 _pid, uint256 _amount) external;
    // function vaultFees() external view returns (VaultFees calldata);
    function earn(address _to) external; // Main want token compounding function
    function deposit(address _from, address _to, uint256 _wantAmt, uint256 _sharesTotal) external returns (uint256);
    function withdraw(address _from, address _to, uint256 _wantAmt, uint256 _userShares, uint256 _sharesTotal) external returns (uint256 sharesRemoved, uint256 wantAmt);
    function setFees(VaultFees calldata _fees) external; //vaulthealer uses this to update configuration
    function panic() external;
    function unpanic() external;
        // Univ2 router used by this strategy
    function settings() external view returns (VaultSettings memory);
}