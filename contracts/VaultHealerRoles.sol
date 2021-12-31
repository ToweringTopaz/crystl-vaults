// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "hardhat/console.sol";

contract VaultHealerRoles is AccessControlEnumerable {


    bytes32 public FEE_SETTER = keccak256("FEE_SETTER");
    bytes32 public BOOST_ADMIN = keccak256("BOOST_ADMIN");
    bytes32 public PAUSER = keccak256("PAUSER");
    bytes32 public SETTINGS_SETTER = keccak256("SETTINGS_SETTER");
    bytes32 public POOL_ADDER = keccak256("POOL_ADDER");
    bytes32 public PATH_SETTER = keccak256("PATH_SETTER");

    bytes32 public STRATEGY = keccak256("STRATEGY");
    bytes32 public BOOSTPOOL = keccak256("BOOSTPOOL");

    constructor (address _owner) {
        _setupRole(DEFAULT_ADMIN_ROLE, _owner);
        _setupRole(FEE_SETTER, _owner);
        _setupRole(BOOST_ADMIN, _owner);
        _setupRole(PAUSER, _owner);
        _setupRole(POOL_ADDER, _owner);
        _setupRole(PATH_SETTER, _owner);

        _setRoleAdmin(STRATEGY, POOL_ADDER);
        _setRoleAdmin(BOOSTPOOL, BOOST_ADMIN);
    }

    function owner() external view returns (address) {
        return getRoleMember(DEFAULT_ADMIN_ROLE, 0);
    }

}