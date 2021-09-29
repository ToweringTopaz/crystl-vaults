// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface IPathStorage {
    
    function getPath(address a, address b) external view returns (address[] memory path);
    
}