// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/Create2.sol";
import "./VaultHealer.sol";
import "./VaultFeeManager.sol";
import "./Magnetite.sol";
import "./StrategyVHStandard.sol";

contract VaultDeployer {

    address public immutable magnetite;
    address public immutable feeman;
    address public immutable strategyImpl;
    address public immutable zap;
    address public immutable vaultHealer;

    constructor(uint[3] salts) {
        magnetite = Create2.deploy(0, salts[0], type(Magnetite).creationCode);
        feeman = Create2.deploy(0, salts[1], type(VaultFeeManager).creationCode);
        strategyImpl = Create2.deploy(0, salts[2], type(VaultFeeManager).creationCode);
        zap = Create2.deploy(0, salts[3], type(QuartzUniV2Zap).creationCode);
        vaultHealer = Create2.deploy(0, salts[4], type(vaultHealer).creationCode);
    }

}
