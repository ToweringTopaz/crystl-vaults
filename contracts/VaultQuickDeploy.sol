// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import "./VaultHealer.sol";
import "./StrategyQuick.sol";

contract VaultQuickDeploy {

    VaultHealer public immutable vaultHealer;
    Strategy public immutable strategy;
    StrategyQuick public immutable strategyQuick;
    VaultHealerAuth public immutable vhAuth;
    QuartzUniV2Zap immutable public zap;
    VaultFeeManager immutable public vaultFeeManager;

    constructor() {
        vaultHealer = new VaultHealer();
        vhAuth = vaultHealer.vhAuth();
        vhAuth.setAccess(msg.sender, 3);
        zap = vaultHealer.zap();
        vaultFeeManager = vaultHealer.vaultFeeManager();

        strategy = new Strategy(vaultHealer);
        strategyQuick = new StrategyQuick(vaultHealer);

        vaultHealer.createVault(strategy, hex'54aff400858dcac39797a81894d9920f16972d1d0000000093f1a40b230000008dbdbe6d243000000ad58d2f2430000018fccc76230000002f940c7023000000034293f21f1cce5908bc605ce5850df2b1059ac008c0788a3ad43d79aa53b09c2eacc313a787d1d6076b7d2f518ad592707da6307eb40e28aa0be2badef0220d500b1d8e8ef31e21c99d1db9a6444d3adf12705d47baba0d66083c52009271faf3f50dcc01023c5d47baba0d66083c52009271faf3f50dcc01023c080d500b1d8e8ef31e21c99d1db9a6444d3adf1270080d500b1d8e8ef31e21c99d1db9a6444d3adf1270');
    }
    




}