// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;
import "./IUniRouter.sol";
interface IMagnetite {
    function findAndSavePath(address _router, address a, address b) external returns (address[] memory path);
    function overridePath(address router, address[] calldata _path) external;
}