// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IStrategy.sol";

interface IVaultHealer {
    function poolInfo(uint256 pid) external view returns (IERC20 want, IStrategy strat);
    function deposit(uint256 _pid, uint256 _wantAmt, address _to) external;
    function poolLength() external view returns (uint);
}