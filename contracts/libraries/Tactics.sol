// SPDX-License-Identifier: GPLv2

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/Address.sol";
import "hardhat/console.sol";

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
        bytes memory generatedCall = _generateCall(uint24(TacticsA.unwrap(tacticsA) >> 72), uint64(TacticsA.unwrap(tacticsA)), 0); //pid, vst call, 0

        address masterchef = address(uint160(TacticsA.unwrap(tacticsA) >> 96));
        bytes memory returndata = masterchef.functionStaticCall(generatedCall, "Tactics: staticcall failed");
        assembly {
            amountStaked := mload(add(returndata, add(0x20,returnvarPosition)))
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
        bytes memory generatedCall = _generateCall(uint24(TacticsA.unwrap(tacticsA) >> 72), uint64(TacticsB.unwrap(tacticsB) >> offset), amount);
        address masterchef = address(uint160(TacticsA.unwrap(tacticsA) >> 96));
        masterchef.functionCall(generatedCall, "Tactics: call failed");
        
    }

    function _generateCall(uint24 pid, uint64 encodedCall, uint amount) public view returns (bytes memory generatedCall) {
        generatedCall = abi.encodePacked(bytes4(bytes8(encodedCall)));

        for (bytes4 params = bytes4(bytes8(encodedCall) << 32); params != 0; params <<= 4) {
            bytes4 p = params & 0xf0000000;
            uint256 word;
            if (p == 0x20000000) {
                word = pid;
            } else if (p == 0x30000000) {
                word = uint(uint160(address(this)));
            } else if (p == 0x40000000) {
                word = amount;
            } else if (p != 0xf0000000) {
                revert("Tactics: invalid tactic");
            }
            generatedCall = abi.encodePacked(generatedCall, word);
        }
    }
}
