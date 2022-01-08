// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IBoostPool {
    function bonusEndBlock() external view returns (uint256);
    function STAKE_TOKEN_VID() external view returns (uint256);
}