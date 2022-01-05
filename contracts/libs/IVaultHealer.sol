// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IStrategy.sol";
interface IVaultHealer is IERC1155 {

    function vaultInfo(uint vid) external view returns (IERC20 want, IStrategy strat);
    function deposit(uint pid, uint wantAmt, address to) external;
    function settings() external view returns (VaultSettings memory);
    function executePendingDeposit(address _to, uint _amount) external;
}