// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./Magnetite.sol";
import "./VaultHealerBase.sol";

//Enables strategy contracts to function as ERC20 share tokens
abstract contract VaultHealerERC20 is VaultHealerBase {    
    /////////ERC20 functions for shareTokens, enabling boosted vaults
    //The findPid function ensures that the caller is a valid strategy and maps the address to its pid
    function erc20TotalSupply() external view returns (uint256) {
        uint pid = findPid(msg.sender); //authenticates as strategy
        return _poolInfo[pid].sharesTotal;
    }
    function erc20BalanceOf(address account) external view returns (uint256) {
        uint pid = findPid(msg.sender); //authenticates as strategy
        return _poolInfo[pid].user[account].shares;
    }
    function erc20Transfer(address sender, address recipient, uint256 amount) external nonReentrant returns (bool) {
        uint pid = findPid(msg.sender); //authenticates as strategy
        UserInfo storage _sender = _poolInfo[pid].user[sender];
        UserInfo storage _recipient = _poolInfo[pid].user[recipient];
        require(_sender.shares >= amount, "VaultHealer: insufficient balance");
        _sender.shares -= amount;
        _recipient.shares += amount;
        return true;
    }
    function erc20Allowance(address owner, address spender) external view returns (uint256) {
        uint pid = findPid(msg.sender); //authenticates as strategy
        return _poolInfo[pid].user[owner].allowances[spender];
    }
    function erc20Approve(address owner, address spender, uint256 amount) external nonReentrant returns (bool) {
        uint pid = findPid(msg.sender); //authenticates as strategy
        _poolInfo[pid].user[owner].allowances[spender] = amount;
        return true;
    }
    function erc20TransferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external nonReentrant returns (bool) {
        uint pid = findPid(msg.sender); //authenticates as strategy
        UserInfo storage _sender = _poolInfo[pid].user[sender];
        UserInfo storage _recipient = _poolInfo[pid].user[recipient];
        require(_sender.shares >= amount, "VaultHealer: insufficient balance");
        require(_sender.allowances[recipient] >= amount, "VaultHealer: insufficient allowance");
        _sender.allowances[recipient] -= amount;
        _sender.shares -= amount;
        _recipient.shares += amount;
        return true;
    }
}