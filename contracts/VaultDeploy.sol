// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import "./VaultHealer.sol";
import "./StrategyQuick.sol";
import "./BoostPool.sol";

contract VaultDeploy {

    VaultHealer public immutable vaultHealer;
    Strategy public immutable strategy;
    StrategyQuick public immutable strategyQuick;
    VaultHealerAuth public immutable vhAuth;
    QuartzUniV2Zap immutable public zap;
    VaultFeeManager immutable public vaultFeeManager;
    BoostPool immutable public boostPoolImpl;

    constructor() {
        vaultHealer = new VaultHealer();
        vhAuth = vaultHealer.vhAuth();
        vhAuth.setAccess(msg.sender, 3);
        zap = vaultHealer.zap();
        vaultFeeManager = vaultHealer.vaultFeeManager();

        strategy = new Strategy(vaultHealer);
        strategyQuick = new StrategyQuick(vaultHealer);
        boostPoolImpl = new BoostPool(address(vaultHealer));
    }
    




}