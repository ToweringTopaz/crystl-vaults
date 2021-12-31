// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./VaultHealerBoostedPools.sol";
import "./Magnetite.sol";

contract VaultHealer is VaultHealerBoostedPools {
    
    Magnetite public magnetite;

    constructor(VaultFees memory _fees, VaultFee memory _withdrawFee)
        VaultHealerRoles(msg.sender)
        VaultHealerBase(_fees, _withdrawFee) 
    {
        magnetite = new Magnetite();
    }
    
    function setPath(address router, address[] calldata path) external onlyRole(PATH_SETTER) {
        magnetite.overridePath(router, path);
    }
}
