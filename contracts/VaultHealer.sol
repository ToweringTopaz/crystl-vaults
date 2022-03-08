// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./QuartzUniV2Zap.sol";
import "./VaultHealerBoostedPools.sol";

contract VaultHealer is VaultHealerBoostedPools {

    QuartzUniV2Zap immutable public zap;

    /// @param _uri Used to retrieve metadata about an ERC1155 token
    /// @param trustedForwarder To provide "gasless" metatransactions. Must be a secure smart contract or address(0), because it will have complete access to user funds
    /// @param _owner The initial privileged user account
    /// @param _feeManager A contract implementing IVaultFeeManager
    constructor(string memory _uri, address trustedForwarder, address _owner, address _feeManager)
        ERC2771Context(trustedForwarder)
        ERC1155(_uri)
		VaultHealerBase(_owner)
        VaultHealerBoostedPools(_owner)
    {
        zap = new QuartzUniV2Zap(address(this));
        vaultFeeManager = IVaultFeeManager(_feeManager);
        _setupRole(DEFAULT_ADMIN_ROLE, _owner);
    }

   function isApprovedForAll(address account, address operator) public view override returns (bool) {
        return super.isApprovedForAll(account, operator) || operator == address(zap) || isTrustedForwarder(operator);
   }

    function setURI(string calldata _uri) external onlyRole("DEFAULT_ADMIN_ROLE") {
        _setURI(_uri);
    }

}

