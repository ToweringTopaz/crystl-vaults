// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

library AddrCalc {

    //returns the first create address for the current address
    function configAddress() internal view returns (address configAddr) {
        assembly ("memory-safe") {
            mstore(0, or(0xd694000000000000000000000000000000000000000001000000000000000000, shl(80,address())))
            configAddr := and(0xffffffffffffffffffffffffffffffffffffffff, keccak256(0, 23)) //create address, nonce 1
        }
    }

    //returns the create address for some address and nonce
    function addressFrom(address _origin, uint _nonce) internal pure returns (address) {
        bytes32 data;
        if(_nonce == 0x00)          data = keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, bytes1(0x80)));
        else if(_nonce <= 0x7f)     data = keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, uint8(_nonce)));
        else if(_nonce <= 0xff)     data = keccak256(abi.encodePacked(bytes1(0xd7), bytes1(0x94), _origin, bytes1(0x81), uint8(_nonce)));
        else if(_nonce <= 0xffff)   data = keccak256(abi.encodePacked(bytes1(0xd8), bytes1(0x94), _origin, bytes1(0x82), uint16(_nonce)));
        else if(_nonce <= 0xffffff) data = keccak256(abi.encodePacked(bytes1(0xd9), bytes1(0x94), _origin, bytes1(0x83), uint24(_nonce)));
        else                        data = keccak256(abi.encodePacked(bytes1(0xda), bytes1(0x94), _origin, bytes1(0x84), uint32(_nonce))); // more than 2^32 nonces not realistic

        return address(uint160(uint256(data)));
    }

    //The nonce of a factory contract that uses CREATE, assuming no child contracts have selfdestructed
    function createFactoryNonce(address _origin) internal view returns (uint nonce) {
        unchecked {
            nonce = 1;
            uint top = 2**32;
            uint p = 1;
            while (p < top && p > 0) {
                address spawn = addressFrom(_origin, nonce + p); //
                if (spawn.code.length > 0) {
                    nonce += p;
                    p *= 2;
                    if (nonce + p > top) p = (top - nonce) / 2;
                } else {
                    top = nonce + p;
                    p /= 2;
                }
            }
        }
    }
}