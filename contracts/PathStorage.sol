// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

//Efficiently and conveniently stores all paths which might be required by a strategy.
abstract contract PathStorage {
    
    uint constant private MAX_PATH = 5;
    mapping(bytes32 => address[MAX_PATH]) private _paths;
    
    event SetPath(address[MAX_PATH] path);
    
    function _setPath(address[] memory _path) internal {
        require(_path.length <= MAX_PATH, "invalid _path.length");
        uint len = MAX_PATH;
        for (uint i; i < MAX_PATH; i++) {
            if (_path[i] == address(0)) {
                len = i;
                for (uint j = i+1; j < MAX_PATH; j++) {
                    require(_path[j] == address(0), "broken path");
                }
                break;
            }
        }
        
        bytes32 hashAB = keccak256(abi.encodePacked(_path[0],_path[len - 1]));
        bytes32 hashBA = keccak256(abi.encodePacked(_path[len - 1],_path[0]));
        address[MAX_PATH] storage pathAB = _paths[hashAB];
        address[MAX_PATH] storage pathBA = _paths[hashBA];
        for(uint i; i < len; i++) {
            pathAB[i] = _path[i];
            pathBA[len - 1 - i] = _path[i];
        }
        emit SetPath(pathAB);
        emit SetPath(pathBA);
        
        //recursively fill sub-paths
        if (len > 2) {
            _autoSubPath(_shl(pathAB, len), len - 1);
            _autoSubPath(_shl(pathBA, len), len - 1);
        }
    }
    function _autoSubPath(address[MAX_PATH] memory _path, uint len) private {
        
        bytes32 hashAB = keccak256(abi.encodePacked(_path[0],_path[len - 1]));
        address[MAX_PATH] storage pathAB = _paths[hashAB];
        
        if (pathAB[0] == address(0)) { //don't replace paths already defined
            bytes32 hashBA = keccak256(abi.encodePacked(_path[len - 1],_path[0]));
            address[MAX_PATH] storage pathBA = _paths[hashBA];
            for(uint i; i < _path.length; i++) {
                pathAB[i] = _path[i];
                pathBA[len - 1 - i] = _path[i];
            }
            emit SetPath(pathAB);
            emit SetPath(pathBA);
            
            //recursively fill sub-paths
            if (len > 2) {
                _autoSubPath(_shl(pathAB, len), len - 1);
                _autoSubPath(_shl(pathBA, len), len - 1);
            }
        }
    }
    function _shl(address[MAX_PATH] memory _path, uint len) private pure returns (address[MAX_PATH] memory path) {
        for (uint i; i < len - 1; i++) {
            path[i] = _path[i+1];
        }
    }
    function _len(address[MAX_PATH] memory _path) private pure returns (uint len) {
        for (uint i; i < MAX_PATH; i++) {
            if (_path[i] == address(0)) return i;
        }
        return MAX_PATH;
    }
    function getPath(address a, address b) public view returns (address[] memory path) {
        if (a == b) {
            path = new address[](1);
            path[0] = a;
            return path;
        }
        bytes32 hashAB = keccak256(abi.encodePacked(a, b));
        address[MAX_PATH] storage _path = _paths[hashAB];
        path = new address[](_len(_path));
        require(path.length > 0, "path not found");
        
        for (uint i; i < path.length; i++) {
            path[i] = _path[i];
        }
        
    }
    
}