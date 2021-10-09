// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./BaseStrategyVaultHealer.sol";

//Provides ERC20 functionality, providing tradeable share tokens and enabling boosted vaults
abstract contract BaseStrategyVHERC20 is BaseStrategyVaultHealer, IERC20 {
    
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    
    function setNameSymbol(string calldata _name, string calldata _symbol) external onlyGov {
        if (bytes(_name).length > 0) name = _name;
        if (bytes(_symbol).length > 0) symbol = _symbol;
    }
    
    function totalSupply() external override view returns (uint256) {
        return vaultHealer.erc20TotalSupply();
    }
    function balanceOf(address account) external override view returns (uint256) {
        return vaultHealer.erc20BalanceOf(account);
    }
    
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        require(vaultHealer.erc20Transfer(msg.sender, recipient, amount));
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }
    function allowance(address owner, address spender) external override view returns (uint256) {
        return vaultHealer.erc20Allowance(owner, spender);
    }
    function approve(address spender, uint256 amount) external override returns (bool) {
        require(vaultHealer.erc20Approve(msg.sender, spender, amount));
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        require(vaultHealer.erc20TransferFrom(sender, recipient, amount));
        emit Transfer(sender, recipient, amount);
        return true;
    }

}