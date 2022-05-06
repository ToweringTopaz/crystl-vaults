// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import "./StrategyQuick.sol";
import "./BoostPool.sol";
import "./VaultHealer.sol";
import "./VaultHealerAuth.sol";
import "./libraries/AmysStakingCo.sol";
import "./QuartzUniV2Zap.sol";

contract VaultDeploy {

    VaultHealer public immutable vaultHealer;
    Strategy public immutable strategy;
    BoostPool immutable public boostPoolImpl;
    VaultHealerAuth immutable public vhAuth;
    VaultFeeManager immutable public vaultFeeManager;
    QuartzUniV2Zap immutable public zap;

    constructor(uint nonce) {
        require(address(this) == AmysStakingCo.addressFrom(msg.sender, nonce), "wrong nonce");
				
        vhAuth = new VaultHealerAuth(address(this));

        vhAuth.setAccess(0xCE34Ccb6481fdc85953fd870343b24816A325351, 3);
        vhAuth.setAccess(0xB2a28925Eb734ecAA1844c5e0f9B1Ac439ad1834, 2);
        vhAuth.setAccess(0x94b93044f635f6E12456374EC1C2EeaE6D8eD945, 2);
        vhAuth.setAccess(0xcA8DCe54d78b5a952F5C8220ee7e43E98C252C76, 2);
        vhAuth.setAccess(0x0894417Dfc569328617FC25DCD6f0B5F4B0eb323, 2);
        vhAuth.setAccess(0x9D7F6d3CD9793282a604DA7dC7fD02b4cAE84198, 1);
        vhAuth.setAccess(0xaE2F96f3c43443a648bf35E1064AD7457778C585, 1);

        vaultFeeManager = new VaultFeeManager(address(vhAuth));

        vaultFeeManager.setDefaultEarnFees([0x5386881b46C37CdD30A748f7771CF95D7B213637, address(0), address(0)], [block.chainid == 137 ? 300 : 500, 0, 0]);
        vaultFeeManager.setDefaultWithdrawFee(0x5386881b46C37CdD30A748f7771CF95D7B213637, 10);

        vaultHealer = VaultHealer(AmysStakingCo.addressFrom(msg.sender, nonce+1));
        require(address(vaultHealer).code.length == 0, "vh/wrong nonce");
        zap = new QuartzUniV2Zap(address(vaultHealer));

        strategy = new Strategy(vaultHealer);
        boostPoolImpl = new BoostPool(address(vaultHealer));

        vhAuth.setAccess(address(this), 0);
    }


}