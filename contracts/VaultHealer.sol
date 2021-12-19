// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./VaultHealerGate.sol";
import "./Magnetite.sol";

contract VaultHealer is VaultHealerGate, Magnetite {
    
    constructor(VaultFees memory _fees, VaultFee memory _withdrawFee)
        VaultHealerBase(_fees, _withdrawFee) {}
    
    //allows strats to generate paths
    function pathAuth() internal override view returns (bool) {
        return super.pathAuth() || isStrat(msg.sender);
    }
    
    function setPath(address router, address[] calldata path) external onlyOwner {
        _setPath(router, path, LibMagnetite.AutoPath.MANUAL);
    }
}
