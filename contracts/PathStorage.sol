// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./libs/LibPathStorage.sol";

abstract contract PathStorage {
    
    uint constant private MAX_PATH = 5;
    mapping(bytes32 => address[MAX_PATH]) private _paths;
    
    function _setPath(address[] memory _path) internal {
        LibPathStorage._setPath(_paths, _path);
    }
    function getPath(address a, address b) public view returns (address[] memory path) {
        return LibPathStorage.getPath(_paths, a, b);
    }
    
}