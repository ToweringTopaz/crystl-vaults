// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IERC20Upgradeable as IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC20MetadataUpgradeable as IERC20Metadata} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "./IBoostPool.sol";

import "./ITactic.sol";
import "./IUniPair.sol";
import "./IUniRouter.sol";
import "./IUniFactory.sol";
import "./IWETH.sol";
import "./IMiniChefV2.sol";
import "./IVaultHealer.sol";
import "./IMagnetite.sol";
import "./IStrategy.sol";