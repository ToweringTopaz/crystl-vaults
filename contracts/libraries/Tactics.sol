// SPDX-License-Identifier: GPLv2

pragma solidity ^0.8.14;

import "@openzeppelin/contracts/utils/Address.sol";

/// @title Tactics
/// @author ToweringTopaz
/// @notice Provides a generic method which vault strategies can use to call deposit/withdraw/balance on stakingpool or masterchef-like contracts
library Tactics {
    using Address for address;

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
		e: the number 1/boolean true
        4: specified amount
        3: address(this)
        2: pid
    */
    type TacticsA is bytes32;
    type TacticsB is bytes32;

    function masterchef(TacticsA tacticsA) internal pure returns (address) {
        return address(bytes20(TacticsA.unwrap(tacticsA)));
    }  
    function pid(TacticsA tacticsA) internal pure returns (uint24) {
        return uint24(bytes3(TacticsA.unwrap(tacticsA) << 160));
    }  
    function vaultSharesTotal(TacticsA tacticsA) internal view returns (uint256 amountStaked) {
        uint returnvarPosition = uint8(uint(TacticsA.unwrap(tacticsA)) >> 64); //where is our vaultshares in the return data
        uint64 encodedCall = uint64(uint(TacticsA.unwrap(tacticsA)));
        if (encodedCall == 0) return 0;
        bytes memory data = _generateCall(pid(tacticsA), encodedCall, 0); //pid, vst call, 0
        data = masterchef(tacticsA).functionStaticCall(data, "Tactics: staticcall failed");
        assembly ("memory-safe") {
            amountStaked := mload(add(data, add(0x20,returnvarPosition)))
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
        uint64 encodedCall = uint64(uint(TacticsB.unwrap(tacticsB)) >> offset);
        if (encodedCall == 0) return;
        bytes memory generatedCall = _generateCall(pid(tacticsA), encodedCall, amount);
        masterchef(tacticsA).functionCall(generatedCall, "Tactics: call failed");
        
    }

    function _generateCall(uint24 _pid, uint64 encodedCall, uint amount) private view returns (bytes memory generatedCall) {

        generatedCall = abi.encodePacked(bytes4(bytes8(encodedCall)));

        for (bytes4 params = bytes4(bytes8(encodedCall) << 32); params != 0; params <<= 4) {
            bytes1 p = bytes1(params) & bytes1(0xf0);
            uint256 word;
            if (p == 0x20) {
                word = _pid;
            } else if (p == 0x30) {
                word = uint(uint160(address(this)));
            } else if (p == 0x40) {
                word = amount;
			} else if (p == 0xe0) {
				word = 1;
            } else if (p != 0xf0) {
                revert("Tactics: invalid tactic");
            }
            generatedCall = abi.encodePacked(generatedCall, word);
        }
    }
}
