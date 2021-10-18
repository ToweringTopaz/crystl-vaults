// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./VaultHealerGate.sol";
import "./VaultHealerERC20.sol";
import "./Magnetite.sol";

contract VaultHealer is VaultHealerGate, VaultHealerERC20, Magnetite {
    
    constructor(VaultFees memory _fees)
        VaultHealerBase(_fees) {}
    
    //allows strats to generate paths
    function pathAuth() internal override view returns (bool) {
        return super.pathAuth() || isStrat(msg.sender);
    }
    
    function setPath(address router, address[] calldata path) external onlyOwner {
        _setPath(router, path, LibMagnetite.AutoPath.MANUAL);
    }
}
