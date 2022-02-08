// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

/*

Deploys ERC-1167 compliant minimal proxies whose address is determined only by a salt, not the implementation target

Proxy init bytecode: 

    15 bytes: 3d3d3d3d3d3d3d335afa503d3e3df3

    3d is returndatasize, which is zero if this call frame has not yet made a call of its own
    3d3d3d3d3d3d : 0 0 0 0 0 0 
    33 caller         :  0 0 0 0 0 0 caller
    5a gas            :  0 0 0 0 0 0 caller gas
    fa staticcall     : 0 0 0 success
    50 pop            : 0 0 0
    3d returndatasize : 0 0 0 size
    3e returndatacopy : 0
    3d returndatasize : 0 size
    f3 return         :

*/

contract Cavendish {

    bytes32 public constant PROXY_INIT_HASH = keccak256(abi.encodePacked(bytes15(0x3d3d3d3d3d3d3d335afa503d3e3df3)));

    bytes32 private implementation;

    function clone(address _implementation, bytes32 salt) public returns (address instance) {

        require(_implementation != address(0), "ERC1167: zero address");
        assembly {
            sstore(implementation.slot, shl(96, _implementation))
            mstore(0, 0x3d3d3d3d3d3d3d335afa503d3e3df3)
            instance := create2(0, 0x11, 15, salt)
            sstore(implementation.slot, 0)
        }
        require(instance != address(0), "ERC1167: create2 failed");
    }

    function computeProxyAddress(bytes32 salt) public view returns (address) {
        return computeProxyAddress(salt, address(this));
    }

    function computeProxyAddress(
        bytes32 salt,
        address deployer
    ) public pure returns (address) {
        bytes32 _data = keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, PROXY_INIT_HASH));
        return address(uint160(uint256(_data)));
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

