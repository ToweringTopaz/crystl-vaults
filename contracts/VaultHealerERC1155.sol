// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "./VaultHealerBase.sol";

abstract contract VaultHealerERC1155 is ERC1155, VaultHealerBase {

    mapping(uint192 => uint256) private _balanceOffset; //similar to rewardDebt
    mapping(uint256 => uint256) private _totalSupply;
    mapping(uint32 => uint256) private _totalCompounding;
    mapping(uint32 => uint256) private _totalExports;
    mapping (uint192 => EnumerableSet.UintSet) private _allImportingTokens;

    function totalSupply(uint256 id) public view virtual returns (uint256) {
        return _totalSupply[id];
    }
    //Total autocompounding shares for a vault; the old "sharesTotal"
    function totalCompounding(uint32 vid) public view virtual returns (uint256) { // 0x00...0000000000000001 autocompounding, not maximizers
        return _totalCompounding[vid];
    }
    //These are want tokens (1:1 value) excluded from autocompounding, maximizing other vaults
    function totalExports(uint32 vid) public view virtual returns (uint256) { // maximizer from a to b: 0x00...0000000b0000000a (tokens in a, earnings buy shares in b)
        return _totalExports[vid];
    }
    function exists(uint256 id) public view virtual returns (bool) {
        return _totalSupply[id] > 0;
    }
    
    //These are the tokens which entitle the account to value in vid
    function allImportingTokensLength(address account, uint32 vid) public view virtual returns (uint length) {
        uint192 key = uint192(uint160(account)) << 32 | vid;
        return EnumerableSet.length(_allImportingTokens[key]);
    }
    function allImportingTokensAt(address account, uint32 vid, uint256 index) public view virtual returns (uint id) {
        uint192 key = uint192(uint160(account)) << 32 | vid;
        return EnumerableSet.at(_allImportingTokens[key], index);
    }
    function allImportingTokensAdd(address account, uint32 vid, uint256 value) public virtual returns (bool success) {
        uint192 key = uint192(uint160(account)) << 32 | vid;
        return EnumerableSet.add(_allImportingTokens[key], value);
    }
    function allImportingTokensRemove(address account, uint32 vid, uint256 value) public virtual returns (bool success) {
        uint192 key = uint192(uint160(account)) << 32 | vid;
        return EnumerableSet.remove(_allImportingTokens[key], value);
    }
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);

        if (from == address(0)) {
            for (uint256 i; i < ids.length; ++i) {
                uint256 id = ids[i];
                _totalSupply[id] += amounts[i];
                if (id > 0) {
                    if (id < 2**32) {
                        _totalCompounding[uint32(id)] += amounts[i];
                    } else {
                        _totalExports[uint32(id)] += amounts[i];
                    }
                }
            }
        } else {
            for (uint256 i; i < ids.length; ++i) {
                uint256 id = ids[i];
                if (id > 0) {
                    if (id < 2**32) {
                        _totalCompounding[uint32(id)] += amounts[i];
                    } else {
                        _totalExports[uint32(id)] += amounts[i];
                    }
                }
        }
        
        if (to == address(0)) {
            for (uint256 i = 0; i < ids.length; ++i) {
                uint256 id = ids[i];
                _totalSupply[id] -= amounts[i];
            
                if (id > 0) {
                    if (id < 2**32) {
                        _totalCompounding[uint32(id)] -= amounts[i];
                    } else {
                        _totalExports[uint32(id)] -= amounts[i];
                    }
                }
            }
        }
    }
    function balanceOf(address account, uint256 id) public view virtual override returns (uint256 amount) {
        amount = super.balanceOf(account, id);
        if (id < 2**32) {
            for (uint i; i < allImportingTokensLength(account, id); ++i) {
                uint importID = allImportingTokensAt(account, id, i);
                uint importTotalSupply = totalSupply(importID);
                //Account owns shares of importID whose strategy owns shares of id
                if (importTotalSupply > 0) 
                    amount += super.balanceOf(account, importID) * super.balanceOf(_vaultInfo[uint32(importID)].strat, id) / importTotalSupply;
            }
            uint192 key = uint192(uint160(account)) << 32 | id;
            amount -= _balanceOffset[key]; //Like rewardDebt, this negates pool tokens to which the user isn't entitled
        }
    }

}