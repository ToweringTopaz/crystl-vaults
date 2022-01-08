// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import {IERC20Upgradeable as IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IMagnetite {
    function findAndSavePath(address _router, IERC20 a, IERC20 b) external returns (IERC20[] memory path);
    function overridePath(address router, IERC20[] calldata _path) external;
}