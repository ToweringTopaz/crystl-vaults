// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IVaultHealer {
    
    function executePendingDeposit(address _to, uint256 _amount) external;
    function owner() external view returns (address);
    function sharesTotal(address _strat) external view returns (uint);
}