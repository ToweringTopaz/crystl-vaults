// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import "./QuartzUniV2Zap.sol";
import "./VaultHealerBoostedPools.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";


contract VaultHealer is VaultHealerBoostedPools, Multicall {

    QuartzUniV2Zap immutable public zap;

    constructor()
        ERC1155("")
    {
        zap = new QuartzUniV2Zap(address(this));
    }

   function isApprovedForAll(address account, address operator) public view override returns (bool) {
        return super.isApprovedForAll(account, operator) || operator == address(zap);
   }

    function setURI(string calldata _uri) external auth {
        _setURI(_uri);
    }

    function stakedWantTokens(address account, uint vid) external view returns (uint) {
        uint shares = balanceOf(account, vid);
        return shares == 0 ? 0 : strat(vid).wantLockedTotal() * shares / totalSupply[vid];
    }

}

