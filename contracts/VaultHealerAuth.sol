// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract VaultHealerAuth is AccessControlEnumerable {

    bytes32 constant FEE_SETTER = keccak256("FEE_SETTER");
    bytes32 constant CREATE_ADMIN = keccak256("CREATE_ADMIN");
    bytes32 constant PAUSE_ADMIN = keccak256("PAUSE_ADMIN");

    constructor(address owner) {
        _setAccess(owner, 3);
        _setRoleAdmin(bytes4(keccak256("createVault(address,bytes)")), CREATE_ADMIN);
        _setRoleAdmin(bytes4(keccak256("createMaximizer(uint256,bytes)")), CREATE_ADMIN);
        _setRoleAdmin(bytes4(keccak256("createBoost(uint256,address,bytes)")), CREATE_ADMIN);
        _setRoleAdmin(bytes4(keccak256("pause(uint256,bool)")), PAUSE_ADMIN);
        _setRoleAdmin(bytes4(keccak256("setAutoEarn(uint256,bool,bool)")), PAUSE_ADMIN);
        _setRoleAdmin(bytes4(keccak256("unpause(uint256)")), PAUSE_ADMIN);
    }

    function setAccess(address account, uint level) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setAccess(account, level);
    }

    //Sets an account's roles to match a predefined tiered list, with 3 being the highest level. These correspond to VaultHealer function selectors.
    function _setAccess(address account, uint level) private {

        if (level > 3) revert("Invalid access level");

        function(bytes32,address) update = _revokeRole;

        if (level == 3) update = _grantRole; //Owner-level access, controlling fees and permissions

        update(DEFAULT_ADMIN_ROLE, account);
        update(CREATE_ADMIN, account);
        update(PAUSE_ADMIN, account);
        update(FEE_SETTER, account);
        update(bytes4(keccak256("setURI(string)")), account);

        if (level == 2) update = _grantRole; //Vault creators

        update(bytes4(keccak256("createVault(address,bytes)")), account);
        update(bytes4(keccak256("createMaximizer(uint256,bytes)")), account);
        update(bytes4(keccak256("createBoost(uint256,address,bytes)")), account);            

        if (level == 1) update = _grantRole; //Pausers

        update(bytes4(keccak256("setAutoEarn(uint256,bool,bool)")), account);
        update(bytes4(keccak256("unpause(uint256)")), account);
        update(bytes4(keccak256("pause(uint256,bool)")), account);

    }

}