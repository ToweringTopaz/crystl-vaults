// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Vault} from "./Vault.sol";
import {IERC20Upgradeable as IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./IUniRouter.sol";
import "./Fee.sol";

interface IStrategy {
    function initEncode(
        IERC20 _wantToken,
        address _masterchefAddress,
        address _tacticAddress,
        uint256 _pid,
        Vault.Settings calldata _settings,
        IERC20[] calldata _earned,
        uint256 _targetVid //maximizer target
    ) external pure returns (bytes memory data);
    function _destroy_() external;
    function initialize (bytes calldata data) external;
    function setSettings(Vault.Settings calldata _settings) external;
    function wantToken() external view returns (IERC20); // Want address
    //function boostPoolAddress() external view returns (address);
    function wantLockedTotal() external view returns (uint256); // Total want tokens managed by strategy
    //function accRewardTokensPerShare() external view returns (uint256);
    //function increaseRewardDebt(address _user, uint256 _amount) external;
    //function getRewardDebt(address _user) external view returns (uint256);
    //function UpdatePoolAndWithdrawCrystlOnWithdrawal(address _from, uint256 _amount, uint256 _userWant) external;
    //function UpdatePoolAndRewarddebtOnDeposit(address _to, uint256 _amount) external;
    function isMaximizer() external view returns (bool);
    function targetVault() external view returns (IStrategy);
    function maximizerRewardToken() external view returns (IERC20);
    function withdrawMaximizerReward(uint256 _pid, uint256 _amount) external;
    function earn(Fee.Data[3] memory fees) external returns (bool success, uint256 _wantLockedTotal); // Main want token compounding function
    function deposit(uint256 _wantAmt, uint256 _sharesTotal) external returns (uint256);
    function withdraw(uint256 _wantAmt, uint256 _userShares, uint256 _sharesTotal) external returns (uint256 sharesRemoved, uint256 wantAmt);
    function panic() external;
    function unpanic() external;
        // Univ2 router used by this strategy
    //function settings() external view returns (Vault.Settings memory);
    function router() external view returns (IUniRouter);
}