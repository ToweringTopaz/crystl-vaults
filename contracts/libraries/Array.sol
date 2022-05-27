// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

library Array {

    bytes32 constant UNUSED = "UNUSED_MEMORY_MAGIC_WORD"; //todo: use keccak256("UNUSED_MEMORY_MAGIC_WORD");

    function popFirst(bytes32[] memory _self) internal pure returns (bytes32 first, bytes32[] memory self) {
        assembly {
            let len := sub(mload(_self), 1) //new length is 1 less than before
            mstore(_self, UNUSED) //mark slot as unused
            _self := add(_self,0x20) //move array reference point one to the right
            self := _self //return new reference point
            first := mload(_self) //get value we're popping
            mstore(_self, len) //store new length
        }
    }

    function popLast(bytes32[] memory _self) internal pure returns (bytes32[] memory self, bytes32 last) {
        assembly {
            self := _self // reference point is unchanged
            let len := mload(self) //old length
            mstore(self, sub(len, 1)) //store new length (one less than before)

            let end := mul(len, 0x20) //pointer to final array member
            last := mload(end) //final array member
            mstore(end, UNUSED) //mark slot as unused
        }
    }
    
    function popFirst(address[] memory _self) internal pure returns (address first, address[] memory self) {
        bytes32[] memory __self;
        bytes32 __first;

        assembly { __self := _self }

        (__first, __self) = popFirst(__self);
        assembly { 
            first := __first 
            self := __self
        }
    }

    function popLast(address[] memory _self) internal pure returns (bytes32[] memory self, bytes32 last) {
        bytes32[] memory __self; bytes32 __last; //initialize 
        assembly { __self := _self }
        (__self, __last) = popLast(__self);
        assembly { self := __self        last := __last }
    }
}