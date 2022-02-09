// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./QuartzUniV2Zap.sol";
import "./VaultHealerBoostedPools.sol";

contract VaultHealer is VaultHealerBoostedPools {

    QuartzUniV2Zap immutable public zap;

    constructor(string memory _uri, address _owner, address _feeManager)
        ERC1155(_uri)
		VaultHealerBase(_owner)
        VaultHealerBoostedPools(_owner)
    {
        zap = new QuartzUniV2Zap(address(this));
        vaultFeeManager = IVaultFeeManager(_feeManager);
        _setupRole(DEFAULT_ADMIN_ROLE, _owner);
    }

   function isApprovedForAll(address account, address operator) public view override returns (bool) {
        return super.isApprovedForAll(account, operator) || operator == address(zap);
   }
}

