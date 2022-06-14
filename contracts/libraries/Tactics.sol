// SPDX-License-Identifier: GPLv2

pragma solidity ^0.8.14;

import "@openzeppelin/contracts/utils/Address.sol";

/// @title Tactics
/// @author ToweringTopaz
/// @notice Provides a generic method which vault strategies can use to call deposit/withdraw/balance on stakingpool or masterchef-like contracts
library Tactics {
    using Address for address;
    using Tactics for Tactic;
    using Tactics for bytes32[3];

    uint160 constant MASK_160 = 0x00ffffffffffffffffffffffffffffffffffffffff;
    uint24 constant MASK_24 = 0xffffff;
    uint8 constant MASK_8 = 0xff;
    bytes32 constant LMASK_64 = 0xffffffffffffffff000000000000000000000000000000000000000000000000;

    type Tactic is bytes8;
    
    struct TacticalData {
        address masterchef;
        uint24 pid;
        uint8 vstReturnPosition;
        Tactic vst; //vaultSharesTotal

        Tactic deposit;
        Tactic withdraw;
        Tactic harvest;
        Tactic emergencyWithdraw;

        Tactic sync;
        Tactic swim; //for future compatibility
        Tactic flip; //for future compatibility
        Tactic flop; //for future compatibility
    }

    enum Action {
        NULL, _NULL, __NULL, VST, DEPOSIT, WITHDRAW, HARVEST, EMERGENCY, SYNC, SWIM, FLIP, FLOP
    }

    function selector(Tactic self) internal pure returns (bytes4 sel) {
        return bytes4(Tactic.unwrap(self));
    }
    function callParams(Tactic self) internal pure returns (bytes4 enc) {
        return bytes4(Tactic.unwrap(self) << 32);
    }
    function exists(Tactic self) internal pure returns (bool) {
        return Tactic.unwrap(self) > 0;
    }

    function unpack(bytes32[3] memory packed) external pure returns (TacticalData memory td) {

        assembly("memory-safe") {
            let outPtr := td
            let inPtr := sub(packed,12)
            mstore(outPtr, and(mload(inPtr), MASK_160)) //chef
            
            outPtr := add(outPtr, 0x20)
            inPtr := add(inPtr, 3)
            mstore(outPtr, and(mload(inPtr), MASK_24)) //pid

            outPtr := add(outPtr, 0x20)
            inPtr := add(inPtr, 1)
            mstore(outPtr, and(mload(inPtr), MASK_8)) //returnvar position

            outPtr := add(outPtr, 0x20)
            inPtr := add(inPtr, 32)
            mstore(outPtr, and(mload(inPtr), LMASK_64)) //vst

            for {let outEnd := add(outPtr, 0x100)} lt(outPtr, outEnd) {} {    
                inPtr := add(inPtr, 8)
                outPtr := add(outPtr, 0x20)
                mstore(outPtr, and(mload(inPtr), LMASK_64))
            }

        }
    }



    /*
    Encoded calls use function selectors followed by single nibbles as follows, with the output packed to 32 bytes:
        0: end of line/null
        f: 32 bytes zero
        4: specified amount
        3: address(this)
        2: pid
    */

    function masterchef(bytes32[3] memory tactics) internal pure returns (address chef) {
        assembly("memory-safe") {
            chef := and(mload(sub(tactics,12)), MASK_160)
        }
    }  
    function pid(bytes32[3] memory tactics) internal pure returns (uint24 p) {
        assembly("memory-safe") {
            p := and(mload(sub(tactics,9)), MASK_24)
        }
    }
    function get(bytes32[3] memory tactics, Action action) internal pure returns (Tactic tactic) {
        assembly("memory-safe") {
            tactic := and(mload(add(tactics,mul(action,8))), LMASK_64)
        }        
    }

    function vaultSharesTotal(bytes32[3] memory tactics) internal view returns (uint256 amountStaked) {
        uint8 returnvarPosition;
        assembly("memory-safe") {
            returnvarPosition := and(mload(sub(tactics,8)), MASK_8)
        }
        Tactic tactic = tactics.get(Action.VST);
        if (tactic.callParams() > 0) {
            bytes memory data = _generateCall(tactics, tactic, 0);
            data = tactics.masterchef().functionStaticCall(data);
            assembly ("memory-safe") {
                amountStaked := mload(add(data, add(0x20,returnvarPosition)))
            }
        }
    }

    function deposit(bytes32[3] memory tactics, uint256 amount) internal {
        Tactic tactic = tactics.get(Action.DEPOSIT);
        if (tactic.exists()) _doCall(tactics, tactic, amount);
    }
    function withdraw(bytes32[3] memory tactics, uint256 amount) internal {
        Tactic tactic = tactics.get(Action.WITHDRAW);
        if (tactic.exists()) _doCall(tactics, tactic, amount);
    }
    function harvest(bytes32[3] memory tactics) internal {
        Tactic tactic = tactics.get(Action.HARVEST);
        if (tactic.exists()) _doCall(tactics, tactic, 0);
    }
    function emergencyVaultWithdraw(bytes32[3] memory tactics) internal {
        //If the emergencyVaultWithdraw tactic is zero, do a withdraw all instead
        Tactic tactic = tactics.get(Action.EMERGENCY);
        if (tactic.exists()) _doCall(tactics, tactic, 0);
        else tactics.withdraw(tactics.vaultSharesTotal());
    }

    function sync(bytes32[3] memory tactics) internal {
        Tactic tactic = tactics.get(Action.SYNC);
        if (tactic.exists()) _doCall(tactics, tactic, 0);
    }

    function swim(bytes32[3] memory tactics) internal {
        Tactic tactic = tactics.get(Action.SWIM);
        if (tactic.exists()) _doCall(tactics, tactic, 0);
    }
    function flip(bytes32[3] memory tactics, uint256 amount) internal {
        Tactic tactic = tactics.get(Action.FLIP);
        if (tactic.exists()) _doCall(tactics, tactic, amount);
    }
    function flop(bytes32[3] memory tactics, uint256 amount) internal {
        Tactic tactic = tactics.get(Action.FLOP);
        if (tactic.exists()) _doCall(tactics, tactic, amount);
    }

    function _doCall(bytes32[3] memory tactics, Tactic tactic, uint amount) private {
        tactics.masterchef().functionCall(_generateCall(tactics, tactic, amount));
    }

    function _generateCall(bytes32[3] memory tactics, Tactic tactic, uint amount) private view returns (bytes memory generatedCall) {

        generatedCall = abi.encodePacked(tactic.selector());

        for (bytes4 params = tactic.callParams(); params != 0; params <<= 4) {
            bytes4 p = params & bytes4(0xf0000000);
            uint256 word;
            if (p == 0x20000000) {
                word = tactics.pid();
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
