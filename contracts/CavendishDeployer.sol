// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

/*

Deploys ERC-1167 compliant minimal proxies whose address is determined only by a salt, not the implementation target

Proxy init bytecode: 

    12 bytes: 602d3481343434335afa50f3

    60 push1 2d       : size
    34 callvalue      : 0 size
    81 dup2           : size 0 size
    34 callvalue      : 0 size 0 size 
    34 callvalue      : 0 0 size 0 size 
    34 callvalue      : 0 0 0 size 0 size 
    33 caller         : caller 0 0 0 size 0 size
    5a gas            : gas caller 0 0 0 size 0 size
    fa staticcall     : success 0 size
    50 pop            : 0 size
    f3 return         : 

*/

import "./libraries/Cavendish.sol";

abstract contract CavendishDeployer {

    bytes12 public constant PROXY_INIT_CODE = hex'602d3481343434335afa50f3';
    bytes32 public constant PROXY_INIT_HASH = keccak256(abi.encodePacked(PROXY_INIT_CODE));

    bytes32 private implementation;

    function clone(address _implementation, bytes32 salt) internal returns (address instance) {

        require(_implementation != address(0), "ERC1167: zero address");
        assembly {
            sstore(implementation.slot, shl(96, _implementation))
            mstore(0, PROXY_INIT_CODE)
            instance := create2(0, 0x00, 12, salt)
            sstore(implementation.slot, 0)
        }
        require(instance != address(0), "ERC1167: create2 failed");
    }

    //Inheriting contracts must call super._fallback(). Will return to the external caller if clone is in progress; otherwise returns internally
    function _fallback() internal virtual view {
        assembly {
            let _implementation := sload(implementation.slot)
            if gt(_implementation, 0) {
                mstore(0x00, 0x363d3d373d3d3d363d7300000000000000000000000000000000000000000000)
                mstore(0x0a, _implementation)
                mstore(0x1e, 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
                return(0x00, 0x2d)
            }
        }
    } 

    fallback() external virtual {
        _fallback();
    }

}

