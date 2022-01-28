// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

//Library FirewallProxies provides some complex functions and contains the actual initcode to deploy these.
//FirewallProxyDeployer is a parent contract which enables deployment. Its temporary storage mechanism allows for the implementation address and 
//  some data to be hardcoded here, without using a constructor or otherwise changing the initcode. This implements the "metamorphic contract" paradigm.
//FirewallProxyImplementation is a parent contract for contracts intended for use behind a FirewallProxy, providing safety checks and access to the 
//implementation address and hardcoded metadata.

contract FirewallProxy /*is IFirewallProxy*/ {

    constructor() { //Constructor must be called by a FirewallProxyDeployer via create2
        //The implementation address and any metadata are, at this point, stored in the FirewallProxyDeployer's storage

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
            //Call back to deployer and get implementation address and metadata length
            let success := call(gas(), caller(), 0, 0x84, 4, 0x00, 96)
            if iszero(success) { revert(0,0) } //Require the call to succeed
            mstore(0x68, mload(0)) //implementation address stored: _X done
            let metadataLength := mload(0x40)
            returndatacopy(0x9e, 0x60, sub(returndatasize(),0x60)) //append metadata if any to bytecode; _Z done

            mstore(0x14, caller()) //_S done        
            mstore(0x00, 0x3660008181823773) //_R done
            mstore(0x34, 0x331415603757633074440c813560e01c141560335733ff5b8091505b30331415) //_V done
            mstore(0x54, 0x6042578091505b8082801560565782833685305afa91506074565b8283368573) //_W done

            //Code starts at 0x18 and ends at 0x9e; sub for length of 0x86
            return(0x18, add(0x86, metadataLength))
        }
    }
}

/*
    Source for the bytecode is below. The logic is simple:

        Trust transactions with no calldata to allow the strategy to receive().
        If the caller is the VaultHealer, selfdestruct if so ordered.
        If the caller is the VaultHealer or the proxy's own address, trust the transaction.
        If the transaction is still untrusted, we do a staticcall to this same proxy address, allowing the tx but ensuring no state changes.
        If the transaction is trusted, do a typical delegatecall. Bubble up errors and return return data.

   object "VHStrategyProxy_deployed" {
        code {
            /// @src 0:155:2469  "contract VHStrategyProxy {..."
            let untrusted := calldatasize() //trust transactions with zero calldata or from vaulthealer or this address
            calldatacopy(0, 0, calldatasize())
            if eq(caller(), 0x7979797979797979797979797979797979797979) {
                let selector := shr(224, calldataload(0))
                if eq(selector, 0x3074440c) { //_destroy_
                    selfdestruct(caller())
                }
                untrusted := 0 
            }
            if eq(caller(), address()) {
                untrusted := 0
            }
            let result
            switch untrusted
            case 0 {
                result := delegatecall(gas(), 0xbebebebebebebebebebebebebebebebebebebebe, 0, calldatasize(), 0, 0)
            } default {
                result := staticcall(gas(), address(), 0, calldatasize(), 0, 0)
            }
            returndatacopy(0, 0, returndatasize())
            if iszero(result) { revert(0, returndatasize()) }
            return(0, returndatasize())
        }
        //data ".metadata" hex""
    }
*/