// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./Fee.sol";

interface IVaultFeeManager {

    function getEarnFees(uint vid) external view returns (Fee.Data[3] memory fees);
    function getWithdrawFee(uint vid) external view returns (address receiver, uint16 rate);
}