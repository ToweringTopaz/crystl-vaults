// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/IAccessControlEnumerable.sol";
import "./IStrategy.sol";

interface IVaultHealer is IAccessControlEnumerable {
    function poolInfo(uint256 pid) external view returns (IERC20 want, IStrategy strat);
    function deposit(uint256 _pid, uint256 _wantAmt, address _to) external;
    function poolLength() external view returns (uint);

    function boostShares(address _user, uint _pid, uint _boostID) external view returns (uint);
}