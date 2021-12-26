// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./VaultHealerBoostedPools.sol";
import "./Magnetite.sol";
import "./QuartzUniV2Zap.sol";

contract VaultHealer is VaultHealerBoostedPools {
    
    bytes32 public constant PATH_SETTER = keccak256("PATH_SETTER");

    Magnetite public magnetite;
    QuartzUniV2Zap public zap;

    constructor(VaultFees memory _fees, VaultFee memory _withdrawFee)
        VaultHealerBase(msg.sender) 
        VaultHealerBoostedPools(msg.sender)
        VaultHealerFees(msg.sender, _fees, _withdrawFee)
        VaultHealerPause(msg.sender)
    {
        magnetite = new Magnetite();
        zap = new QuartzUniV2Zap(this);
        _setupRole(PATH_SETTER, msg.sender);
    }
    
    function setPath(address router, address[] calldata path) external onlyRole(PATH_SETTER) {
        magnetite.overridePath(router, path);
    }
}
