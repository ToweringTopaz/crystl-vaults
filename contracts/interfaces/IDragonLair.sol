// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IDragonLair {
    function enter(uint256 _quickAmount) external;
    
    function leave(uint256 _dQuickAmount) external;
    
    function QUICKBalance(address _account) external view returns (uint256);
}