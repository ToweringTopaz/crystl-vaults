// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "./Strategy.sol";
import "./interfaces/ISaharaDaoStaking.sol";

contract StrategySahara is Strategy {
    using StrategyConfig for StrategyConfig.MemPointer;

    ISaharaDaoStaking public constant SaharaStaking = ISaharaDaoStaking(0x6F132536069F8E35ED029CEd563710CF68fE8E54);

    constructor(IVaultHealer _vaultHealer) Strategy(_vaultHealer) {}

    function _vaultHarvest() internal override {
        super._vaultHarvest();
        SaharaStaking.emergencyWithdraw();
    }
}