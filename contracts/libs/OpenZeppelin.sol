// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {BitMapsUpgradeable as BitMaps} from "@openzeppelin/contracts-upgradeable/utils/structs/BitMapsUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {Create2Upgradeable as Create2} from "@openzeppelin/contracts-upgradeable/utils/Create2Upgradeable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {BitMapsUpgradeable as BitMaps} from "@openzeppelin/contracts-upgradeable/utils/structs/BitMapsUpgradeable.sol";
import {ERC1155HolderUpgradeable as ERC1155Holder} from "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import {OwnableUpgradeable as Ownable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
//import {ReentrancyGuardUpgradeable as ReentrancyGuard} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {AccessControlEnumerableUpgradeable as AccessControlEnumerable} from "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";