// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/proxy/Proxy.sol";

contract VHStrategyProxy is Proxy {

    function _delegate(address implementation) internal virtual override {
        assembly {

            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            //Safe transactions are from this address (will be staticcalls), vaultHealer, or have zero calldata
            let safe := or(or(eq(caller(), 0x7979797979797979797979797979797979797979), iszero(calldatasize())), eq(address(), caller()))
            
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

   function _implementation() internal pure override returns (address) {
        return 0xBEbeBeBEbeBebeBeBEBEbebEBeBeBebeBeBebebe;   
    }

    function _destroy_() external {
        assembly {
            if eq(caller(), 0x7979797979797979797979797979797979797979) {
                selfdestruct(caller())
            }
            invalid()
        }
    }

    function getProxyMetadata() external pure returns (bytes memory) {
        assembly {
            codecopy(0, 0x7f7f, 0xbebe)
            return(0, 0xbebe)
        }
    }
}