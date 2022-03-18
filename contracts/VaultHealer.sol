// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import "./QuartzUniV2Zap.sol";
import "./VaultHealerBoostedPools.sol";

contract VaultHealer is VaultHealerBoostedPools {

    QuartzUniV2Zap immutable public zap;

    constructor(string memory _uri, address /*trustedForwarder*/, address _owner)
        /*ERC2771Context(trustedForwarder)*/
        ERC1155(_uri)
		VaultHealerBase(_owner)
    {
        zap = new QuartzUniV2Zap(address(this));
    }

   function isApprovedForAll(address account, address operator) public view override returns (bool) {
        return super.isApprovedForAll(account, operator) || operator == address(zap) /*|| isTrustedForwarder(operator)*/;
   }

    function setURI(string calldata _uri) external auth {
        _setURI(_uri);
    }

}

