// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import "./QuartzUniV2Zap.sol";
import "./VaultHealerBoostedPools.sol";

contract VaultHealer is VaultHealerBoostedPools {

    QuartzUniV2Zap immutable public zap;

    constructor(address _owner, address withdrawReceiver, uint16 withdrawRate, address[3] memory earnReceivers, uint16[3] memory earnRates)
        ERC1155("")
		VaultHealerBase(_owner, withdrawReceiver, withdrawRate, earnReceivers, earnRates)
    {
        zap = new QuartzUniV2Zap(address(this));
    }

   function isApprovedForAll(address account, address operator) public view override returns (bool) {
        return super.isApprovedForAll(account, operator) || operator == address(zap);
   }

    function setURI(string calldata _uri) external auth {
        _setURI(_uri);
    }

}

