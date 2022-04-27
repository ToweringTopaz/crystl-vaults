// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import "./QuartzUniV2Zap.sol";
import "./VaultHealerBoostedPools.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "./VaultDeploy.sol";

contract VaultHealer is VaultHealerBoostedPools, Multicall {

    QuartzUniV2Zap immutable public zap;

    constructor()
        ERC1155("")
    {
        zap = new QuartzUniV2Zap(address(this));

        address(new VaultDeploy());
    }

   function isApprovedForAll(address account, address operator) public view override returns (bool) {
        return super.isApprovedForAll(account, operator) || operator == address(zap);
   }

    function setURI(string calldata _uri) external auth {
        _setURI(_uri);
    }

    function stakedWantTokens(address account, uint vid) external view returns (uint) {
        uint shares = balanceOf(account, vid);
        return shares == 0 ? 0 : wantLockedTotal(vid) * shares / totalSupply[vid];
    }
    
    function stakedWantTokensBatch(address[] calldata account, uint[] calldata vid) external view returns (uint[] memory amounts) {
        uint[] memory shares = balanceOfBatch(account, vid);
        for (uint i; i < vid.length; i++) {
            amounts[i] = shares[i] == 0 ? 0 : wantLockedTotal(vid[i]) * shares[i] / totalSupply[vid[i]];
        }
    }

    function wantLockedTotal(uint vid) public view returns (uint) {
        return strat(vid).wantLockedTotal();
    }
    function wantLockedTotalBatch(uint[] calldata vids) external view returns (uint[] calldata amounts) {
        amounts = new uint[](vids.length);
        
        for (uint i; i < vids.length; i++) {
            amounts[i] = strat(vid).wantLockedTotal();
    }
}

