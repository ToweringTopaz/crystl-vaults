// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

/*
Deploys ERC-1167 compliant minimal proxies whose address is determined only by a salt, not the implementation target

Proxy init bytecode: 

    11 bytes: 602d80343434335afa15f3

    60 push1 2d       : size
    80 dup1           : size size
    34 callvalue      : 0 size size 
    34 callvalue      : 0 0 size size 
    34 callvalue      : 0 0 0 size size 
    33 caller         : caller 0 0 0 size size
    5a gas            : gas caller 0 0 0 size size
    fa staticcall     : success size
    15 iszero         : 0 size
    f3 return         : 

*/

library Cavendish {

    bytes11 constant PROXY_INIT_CODE = hex'602d80343434335afa15f3';
                                              // literal in line below = keccak256(abi.encodePacked(PROXY_INIT_CODE));
    bytes32 constant PROXY_INIT_HASH = hex'577cbdbf32026552c0ae211272febcff3ea352b0c755f8f39b49856dcac71019';

    //Creates an 1167-compliant minimal proxy whose address is purely a function of the deployer address and the salt
    function clone(address _implementation, bytes32 salt) internal returns (address instance) {

        require(_implementation != address(0), "ERC1167: zero address");
        assembly {
            sstore(PROXY_INIT_HASH, shl(96, _implementation)) //store at slot PROXY_INIT_HASH which should be empty
            mstore(0, PROXY_INIT_CODE)
            instance := create2(0, 0x00, 11, salt)
            sstore(PROXY_INIT_HASH, 0) 
        }
        require(instance != address(0), "ERC1167: create2 failed");
    }
    
    //Standard function to compute a create2 address deployed by this address, but not impacted by the target implemention
    function computeAddress(bytes32 salt) internal view returns (address) {
        return computeAddress(salt, address(this));
    }

    //Standard function to compute a create2 address, but not impacted by the target implemention
    function computeAddress(
        bytes32 salt,
        address deployer
    ) internal pure returns (address) {
        bytes32 _data = keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, PROXY_INIT_HASH));
        return address(uint160(uint256(_data)));
    }

    //Deploying contracts must call this in fallback(). Will return to the external caller if clone is in progress; otherwise returns internally doing nothing
    function _fallback() internal view {
        assembly {
            let _implementation := sload(PROXY_INIT_HASH)
            if gt(_implementation, 0) {
                mstore(0x00, 0x363d3d373d3d3d363d7300000000000000000000000000000000000000000000)
                mstore(0x0a, _implementation)
                mstore(0x1e, 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
                return(0x00, 0x2d)
            }
        }
    }

}