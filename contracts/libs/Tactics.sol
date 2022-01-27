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
            
            32: withdraw selector
            32: withdraw encoded call format
            
            32: harvest selector
            32: harvest encoded call format
            
            32: emergencyVaultWithdraw selector
            32: emergencyVaultWithdraw encoded call format

    Encoded calls use function selectors followed by single nibbles as follows, with the output packed to 32 bytes:
        0: end of line/null
        f: 32 bytes zero
        4: specified amount
        3: address(this)
        2: pid
    */
    type TacticsA is uint256;
    type TacticsB is uint256;

    function generateTactics(
        address masterchef,
        uint24 pid, 
        uint8 vstReturnPosition, 
        uint64 vstCode, //includes selector and encoded call format
        uint64 depositCode, //includes selector and encoded call format
        uint64 withdrawCode, //includes selector and encoded call format
        uint64 harvestCode, //includes selector and encoded call format
        uint64 emergencyCode//includes selector and encoded call format
    ) external pure returns (TacticsA tacticsA, TacticsB tacticsB) {
        assembly {
            tacticsA := or(or(shl(96, masterchef), shl(72, pid)), or(shl(64, vstReturnPosition), vstCode))
            tacticsB := or(or(shl(192, depositCode), shl(128, withdrawCode)), or(shl(64, harvestCode), emergencyCode))
        }
    }

    function vaultSharesTotal(TacticsA tacticsA) internal view returns (uint256 amountStaked) {
        uint returnvarPosition = (TacticsA.unwrap(tacticsA) >> 64) & 0xff; //where is our vaultshares in the return data
        bytes memory generatedCall = _generateCall((TacticsA.unwrap(tacticsA) >> 72) & 0xffffff, TacticsA.unwrap(tacticsA) & 0xffffffffffffffff, 0); //pid, vst call, 0

        assembly {
            let ptr := generatedCall
            let success := staticcall(gas(), shr(96, tacticsA), add(generatedCall, 0x20), generatedCall, generatedCall, add(returnvarPosition, 0x20))
            if iszero(success) { revert(0, 0) }
            amountStaked := mload(add(generatedCall, returnvarPosition))
        }
    }

    function deposit(TacticsA tacticsA, TacticsB tacticsB, uint256 amount) internal {
        _doCall(tacticsA, tacticsB, amount, 192);
    }
    function withdraw(TacticsA tacticsA, TacticsB tacticsB, uint256 amount) internal {
        _doCall(tacticsA, tacticsB, amount, 128);
    }
    function harvest(TacticsA tacticsA, TacticsB tacticsB) internal {
        _doCall(tacticsA, tacticsB, 0, 64);
    }
    function emergencyVaultWithdraw(TacticsA tacticsA, TacticsB tacticsB) internal {
        _doCall(tacticsA, tacticsB, 0, 0);
    }
    function _doCall(TacticsA tacticsA, TacticsB tacticsB, uint256 amount, uint256 offset) private {
        bytes memory generatedCall = _generateCall((TacticsA.unwrap(tacticsA) >> 72) & 0xffffff, (TacticsB.unwrap(tacticsB) >> offset) & 0xffffffffffffffff, amount);

        assembly {
            let success := call(gas(), shr(96, tacticsA), 0, add(generatedCall, 0x20), generatedCall, 0, 0)
            if iszero(success) { revert(0, 0) }
        }
    }

    function _generateCall(uint pid, uint256 encodedCall, uint amount) private view returns (bytes memory generatedCall) {
        assembly {
            generatedCall := mload(0x40) //free memory pointer, will contain length value
            
            //store selector at start of data area, expecting area on left to be overwritten with length;
            // area on right to be overwritten with data or, if number of parameters is zero, ignored
            mstore(add(generatedCall,8), encodedCall) 
            
            let ptr := add(generatedCall,0x24) //place params after selector

            for { let i := 28 } lt(i, 31) { i := sub(i, 4) } { //underflow expected
                switch and(shr(i, encodedCall), 0x0f) // (encodedCall >> i) & 0x0f : isolates a nibble representing some 32-byte word
                case 0 { break }
                case 0x0f { mstore(ptr, 0) }
                case 2 { mstore(ptr, pid) } //pid
                case 4 { mstore(ptr, amount) }
                case 3 { mstore(ptr, address()) } //address(this)
                default { revert(0,0) } //tactic code out of range
                
                ptr := add(ptr, 0x20)

            }
            mstore(generatedCall, sub(ptr, add(generatedCall,0x20))) //store length
        }
    }
}
