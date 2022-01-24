// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./VaultHealerBase.sol";
import "./FirewallProxyDeployer.sol";
import "./libs/FirewallProxies.sol";

abstract contract VaultHealerFactory is VaultHealerBase, FirewallProxyDeployer {

    function createVault(
        address implementation,
        bytes calldata initdata,
        bytes calldata metadata
    ) external nonReentrant {
        address newStrat = deployProxy(implementation, bytes32(_vaultInfo.length), metadata);
        IStrategy(newStrat).initialize(initdata);
        addVault(newStrat);
    }
    
    function strat(uint _vid) public override view returns (IStrategy) {
        return IStrategy(FirewallProxies.computeAddress(bytes32(_vid)));
    }

}