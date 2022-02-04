// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

contract ContractSizer {

    function sizeOf(address a) external view returns (uint size) {
        assembly {
            size := extcodesize(a)
        }
    }

}