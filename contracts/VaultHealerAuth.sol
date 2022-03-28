// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract VaultHealerAuth is AccessControlEnumerable {

    bytes32 constant FEE_SETTER = keccak256("FEE_SETTER");

    constructor(address owner) {
        _setAccess(owner, 3);
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

    function _noop(address, uint) private pure {}
}