// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "./Magnetite.sol";
import "./libraries/Cavendish.sol";
//Automatically generates and stores paths
contract Magneto is AccessControlEnumerable {

    Magnetite immutable public magnetite = Magnetite(Cavendish.computeAddress(bytes32(0)));
    bytes32 constant public PATH_SETTER = keccak256("PATH_SETTER");

    constructor() {
        _grantRole(PATH_SETTER, msg.sender);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        deployMagnetite(address(new Magnetite()));
    }

    function deployMagnetite(address implementation) public {
        Cavendish.clone(implementation, bytes32(0));
        magnetite._init();
    }
    function purgeMagnetite() external {
        magnetite._nuke();
    }

    fallback() external {
        Cavendish._fallback();
        Magnetite _mag = magnetite;
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := call(gas(), _mag, 0, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // call returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

}