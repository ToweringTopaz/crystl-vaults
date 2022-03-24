// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract VaultHealerAuth is AccessControlEnumerable {

    bytes32 constant FEE_SETTER = keccak256("FEE_SETTER");

    constructor(address _owner) {
        _setupRole(DEFAULT_ADMIN_ROLE, _owner);
        _setupRole(FEE_SETTER, _owner);
        _setupRole(bytes4(keccak256("createVault(address,bytes)")), _owner);
        _setupRole(bytes4(keccak256("createMaximizer(uint256,bytes)")), _owner);
        _setupRole(bytes4(keccak256("createBoost(uint256,address,bytes)")), _owner);
        _setupRole(bytes4(keccak256("setAutoEarn(uint256,bool,bool)")), _owner);
        _setupRole(bytes4(keccak256("unpause(uint256)")), _owner);
        _setupRole(bytes4(keccak256("pause(uint256,bool)")), _owner);
        _setupRole(bytes4(keccak256("setURI(string)")), _owner);
    }

    function setAccess(address account, uint level) external onlyRole(DEFAULT_ADMIN_ROLE) {

        if (level > 0) {
            _grantRole(bytes4(keccak256("setAutoEarn(uint256,bool,bool)")), account);
            _grantRole(bytes4(keccak256("unpause(uint256)")), account);
            _grantRole(bytes4(keccak256("pause(uint256,bool)")), account);
        } else {
            _revokeRole(bytes4(keccak256("setAutoEarn(uint256,bool,bool)")), account);
            _revokeRole(bytes4(keccak256("unpause(uint256)")), account);
            _revokeRole(bytes4(keccak256("pause(uint256,bool)")), account);
        }
        if (level > 1) {
            _grantRole(bytes4(keccak256("createVault(address,bytes)")), account);
            _grantRole(bytes4(keccak256("createMaximizer(uint256,bytes)")), account);
            _grantRole(bytes4(keccak256("createBoost(uint256,address,bytes)")), account);
        } else {
            _revokeRole(bytes4(keccak256("createVault(address,bytes)")), account);
            _revokeRole(bytes4(keccak256("createMaximizer(uint256,bytes)")), account);
            _revokeRole(bytes4(keccak256("createBoost(uint256,address,bytes)")), account);            
        }
        if (level > 2) {
            _grantRole(DEFAULT_ADMIN_ROLE, account);
            _grantRole(FEE_SETTER, account);
            _grantRole(bytes4(keccak256("setURI(string)")), account);
        } else {
            _revokeRole(DEFAULT_ADMIN_ROLE, account);
            _revokeRole(FEE_SETTER, account);
            _revokeRole(bytes4(keccak256("setURI(string)")), account);
            
        }
    }

}