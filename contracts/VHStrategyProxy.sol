// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import {IVaultHealer} from "./libs/IVaultHealer.sol";

contract VHStrategyProxy {

    constructor() {
        (address implementation, bytes memory metadata) = IVaultHealer(msg.sender).getProxyData();

        assembly {
            let ptr := mload(0x40)
            mstore(ptr, or(0x3660008181823773000000000000000000000000000000000000000033141560,shl(32, caller())))
            mstore(add(ptr,0x20), 0x3757633074440c813560e01c141560335733ff5b8091505b3033141560425780)
            mstore(add(ptr,0x40), 0x91505b8082801560565782833685305afa91506074565b828336857300000000)
            mstore(add(ptr,0x5c), shl(96,implementation))
            mstore(add(ptr,0x70), 0x5af491505b503d82833e806081573d82fd5b503d81f300000000000000000000)

            let metadataLength := mload(metadata)
            let ptr2 := add(ptr,0x86)
            for { let i := 0 } lt(i, metadataLength) { i := add(i, 0x20) } {
                
                let chunk := mload(add(metadata, add(0x20,i)))
                mstore(add(ptr2, i), chunk)
            }
            return(ptr, add(0x86, metadataLength))
        }
    }
}