// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libs/IUniRouter.sol";
import "./libs/LibMagnetite.sol";
import "hardhat/console.sol";

//Automatically generates and stores paths
contract Magnetite is Ownable {
    
    mapping(bytes32 => address[]) private _paths;

    //Adds or modifies a swap path
    function overridePath(address router, address[] calldata _path) external onlyOwner {
        LibMagnetite._setPath(_paths, router, _path, LibMagnetite.AutoPath.MANUAL);
    }

    function setAutoPath_(address router, address[] calldata _path) external {
        require(msg.sender == address(this));
        LibMagnetite._setPath(_paths, router, _path, LibMagnetite.AutoPath.AUTO);
    }
    function _setPath(address router, address[] calldata _path, LibMagnetite.AutoPath _auto) internal { 
        LibMagnetite._setPath(_paths, router, _path, _auto);
    }
    function findAndSavePath(address router, address a, address b) external returns (address[] memory path) {
        path = getPathFromStorage(router, a, b); // [A C E D B]
        if (path.length == 0) {
            path = LibMagnetite.generatePath(router, a, b);
            if (pathAuth()) {
                LibMagnetite._setPath(_paths, router, path, LibMagnetite.AutoPath.AUTO);

            }
        }
    }
    function viewPath(address router, address a, address b) external view returns (address[] memory path) {
        path = getPathFromStorage(router, a, b); // [A C E D B]
        if (path.length == 0) {
            path = LibMagnetite.generatePath(router, a, b);
        }
    }
    function getPathFromStorage(address router, address a, address b) public view returns (address[] memory path) {
        if (a == b) {
            path = new address[](1);
            path[0] = a;
            return path;
        }
        path = _paths[keccak256(abi.encodePacked(router, a, b))];
    }
    function pathAuth() internal virtual view returns (bool) {
        return msg.sender == tx.origin || msg.sender == owner();
    }
}