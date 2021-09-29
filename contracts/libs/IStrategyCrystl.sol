// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IStrategyCrystl {
    function depositReward(uint256 _depositAmt) external returns (bool);
}