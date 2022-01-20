// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import {IVaultHealer} from "./libs/IVaultHealer.sol";

contract VHStrategyProxy {

    constructor() { //Constructor must be called by a VaultHealer via create2
        //The implementation address and any metadata are, at this point, stored in the calling VaultHealer's storage

        assembly {
                
            /* 
            By careful ordering of mstore operations we can assemble our deployed bytecode in a simple and efficient pattern, accounting for
            zero padding on either side of the desired code.

            Bytecode to be deployed: 

            padding start/code start/end

            _R 0x00/0x18/0x20: 3660008181823773 (first 8 bytes of bytecode)
            _S 0x14/0x20/0x34: 7979797979797979797979797979797979797979 (replaced with caller address)
            _V 0x34/0x34/0x54: 331415603757633074440c813560e01c141560335733ff5b8091505b30331415 (32 bytes pure bytecode)
            _W 0x54/0x54/0x74: 6042578091505b8082801560565782833685305afa91506074565b8283368573 (32 bytes pure bytecode)
            _X 0x68/0x74/0x88: bebebebebebebebebebebebebebebebebebebebe (replaced with implementation address)
            _Y 0x7e/0x88/0x9e: 5af491505b503d82833e806081573d82fd5b503d81f3 (22 bytes end of bytecode)
            _Z 0x9e/0x9e/????: (any metadata)
            

            In order to correctly overwrite zero padding with data:

                store _R after _S
                store _W after _X
                store _X after _Y
            */

            //_Y done; at 0x84 we have 0xad3b358e for the getProxyData() selector (will be overwritten)
            mstore(0x7e, 0xad3b358e5af491505b503d82833e806081573d82fd5b503d81f3)
            //Call back to VaultHealer and get implementation address and metadata length
            let success := call(gas(), caller(), 0, 0x84, 4, 0x00, 64)
            if iszero(success) { revert(0,0) } //Require the call to succeed
            mstore(0x68, mload(0)) //implementation address stored: _X done
            let metadataLength := mload(0x20)
            returndatacopy(0x9e, 0x40, metadataLength) //append metadata if any to bytecode; _Z done

            mstore(0x14, caller()) //_S done        
            mstore(0x00, 0x3660008181823773) //_R done
            mstore(0x34, 0x331415603757633074440c813560e01c141560335733ff5b8091505b30331415) //_V done
            mstore(0x54, 0x6042578091505b8082801560565782833685305afa91506074565b8283368573) //_W done

            //Code starts at 0x18 and ends at 0x9e; sub for length of 0x86
            return(0x18, add(0x86, metadataLength))
        }
    }
}