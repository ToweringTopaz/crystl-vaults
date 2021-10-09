// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

import "./VaultHealerGate.sol";
import "./VaultHealerERC20.sol";
import "./Magnetite.sol";

contract VaultHealer is VaultHealerGate, VaultHealerERC20, Magnetite {
    
    constructor(LibVaultHealer.Config memory _config)
        VaultHealerBase(_config) {}
    
    //allows strats to generate paths
    function pathAuth() internal override view returns (bool) {
        return super.pathAuth() || isStrat(msg.sender);
    }
}
