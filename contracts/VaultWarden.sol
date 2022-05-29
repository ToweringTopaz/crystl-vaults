// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "./VaultFeeManager.sol";
import "./VaultHealerAuth.sol";

contract VaultWarden is VaultHealerAuth, VaultFeeManager {

    constructor() VaultFeeManager(address(this)) {
		
        _setAccess(0xCE34Ccb6481fdc85953fd870343b24816A325351, 3);
        _setAccess(0xB2a28925Eb734ecAA1844c5e0f9B1Ac439ad1834, 2);
        _setAccess(0x94b93044f635f6E12456374EC1C2EeaE6D8eD945, 2);
        _setAccess(0xcA8DCe54d78b5a952F5C8220ee7e43E98C252C76, 2);
        _setAccess(0x0894417Dfc569328617FC25DCD6f0B5F4B0eb323, 2);
        _setAccess(0x9D7F6d3CD9793282a604DA7dC7fD02b4cAE84198, 1);
        _setAccess(0xaE2F96f3c43443a648bf35E1064AD7457778C585, 1);
		
        setDefaultEarnFees([0x5386881b46C37CdD30A748f7771CF95D7B213637, address(0), address(0)], [block.chainid == 137 ? 300 : 500, 0, 0]);
        setDefaultWithdrawFee(0x5386881b46C37CdD30A748f7771CF95D7B213637, 10);

    }

    function _auth() internal override {
        require(hasRole(FEE_SETTER, msg.sender), "!auth");
    }


}