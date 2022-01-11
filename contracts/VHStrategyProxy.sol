// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import {IVaultHealer} from "./libs/IVaultHealer.sol";

contract VHStrategyProxy {

    address immutable VAULTHEALER;
    address immutable IMPLEMENTATION;

    constructor() {
        VAULTHEALER = msg.sender;
        bytes memory metadata;
        (IMPLEMENTATION, metadata) = IVaultHealer(msg.sender).getProxyData();
    }

    function _delegate() internal {
        address vaultHealer = VAULTHEALER;
        address implementation = IMPLEMENTATION;
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            //Safe transactions are from this address (will be staticcalls), vaultHealer, or have zero calldata
            let safe := or(or(eq(caller(), vaultHealer), iszero(calldatasize())), eq(address(), caller()))
            
            let result
            switch safe
            case 0 {
                //This does a staticcall to this address which is then delegated to the implementation. The static lock persists, preventing state changes
                result := staticcall(gas(), address(), 0, calldatasize(), 0, 0)
            }
            default {
                    // Call the implementation.
                // out and outsize are 0 because we don't know the size yet.
                result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
            }

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
    
    fallback() external payable virtual {
        _delegate();
    }
    receive() external payable virtual {
        _delegate();
    }

    function _destroy_() external {
        address vaultHealer = VAULTHEALER;
        assembly {
            if eq(caller(), vaultHealer) {
                selfdestruct(caller())
            }
            invalid()
        }
    }
}