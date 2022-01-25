// SPDX-License-Identifier: GPLv2

pragma solidity ^0.8.0;

library Tactics {

    /*
    This library handles masterchef function call data packed as follows:

        uint256 tacticsA: 
            160: masterchef
            24: pid
            8: position of vaultSharesTotal function's returned amount within the returndata 
            32: selector for vaultSharesTotal
            32: vaultSharesTotal encoded call format

        uint256 tacticsB:
            32: deposit selector
            32: deposit encoded call format
            32: withdraw...
            32: ...
            ...harvest
            ...emergencyVaultWithdraw

    Encoded calls use function selectors followed by single nibbles as follows, with the output packed to 32 bytes:
        0: end of line/null
        f: 32 bytes zero
        4: specified amount
        3: address(this)
        2: pid
        1: masterchefAddress
    */


    function vaultSharesTotal(uint256 tacticsA) internal returns (uint256 amountStaked) {
        return _chefCall(tacticsA, tacticsA & 0xffffffffffffffff, true, 0);
    }

    function deposit(uint256 tacticsA, uint256 tacticsB, uint256 amount) internal {
        _chefCall(tacticsA, tacticsB >> 192, false, amount);
    }

    function withdraw(uint256 tacticsA, uint256 tacticsB, uint256 amount) internal {
        _chefCall(tacticsA, (tacticsB >> 128) & 0xffffffffffffffff, false, amount);
    }
    function harvest(uint256 tacticsA, uint256 tacticsB) internal {
        _chefCall(tacticsA, (tacticsB >> 64) & 0xffffffffffffffff, false, 0);
    }

    function emergencyVaultWithdraw(uint256 tacticsA, uint256 tacticsB) internal {
        _chefCall(tacticsA, tacticsB & 0xffffffffffffffff, false, 0);
    }

    function _chefCall(uint256 tacticsA, uint256 encodedCall, bool vaultshares, uint amount) private returns (uint256 amountStaked) {
        assembly {
            let startptr := mload(0x40) //free memory pointer
            let ptr := add(startptr,4)

            mstore(startptr, shl(192, and(encodedCall, 0xffffffff00000000))) //store selector at start
            
            let masterchef := shr(96, tacticsA)
            let pid := and(shr(72, tacticsA), 0xffffff)

            for { let i := 7 } lt(i, 8) { i := sub(i, 1) } { //underflow expected
                let param
                switch and(shr(mul(4, i), tacticsA), 0x0f) // (tacticsA >> 4*i) & 0x0f : isolates a nibble representing some 32-byte word
                case 0 { break }
                case 0x0f { param := 0 }
                case 4 { param := amount }
                case 3 { param := address() } //address(this)
                case 2 { param := pid } //pid
                case 1 { param := masterchef } //masterchef
                default { revert(0,0) } //tactic code out of range
                
                mstore(ptr, param)
                ptr := add(ptr, 0x20)

            }

            switch vaultshares
            case 1 { //vaultsharestotal
                let returnvarPosition := and(shr(64,tacticsA), 0xff) //where is our vaultshares in the return data
                let success := staticcall(gas(), masterchef, startptr, sub(ptr, startptr), startptr, add(returnvarPosition, 0x20))
                if iszero(success) { revert(0, 0) }
                amountStaked := mload(add(startptr, returnvarPosition))
            } default {
                let success := call(gas(), masterchef, 0, startptr, sub(ptr, startptr), 0, 0)
                if iszero(success) {revert(0, 0) }
            }


        }
    }
}