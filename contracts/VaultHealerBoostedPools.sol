// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import "./VaultHealerGate.sol";
import "./interfaces/IBoostPool.sol";

abstract contract VaultHealerBoostedPools is VaultHealerGate {
    using BitMaps for BitMaps.BitMap;

    bytes32 public constant BOOSTPOOL = keccak256("BOOSTPOOL");
    bytes32 public constant BOOST_ADMIN = keccak256("BOOST_ADMIN");

    BitMaps.BitMap activeBoosts;
    mapping(address => BitMaps.BitMap) userBoosts;
    
    constructor(address _owner) {
        _setupRole(BOOST_ADMIN, _owner);
        _setRoleAdmin(BOOSTPOOL, BOOST_ADMIN);
    }
    function boostPool(uint _boostID) public view returns (IBoostPool) {
        return IBoostPool(Cavendish.computeAddress(bytes32(_boostID)));
    }
    
    function nextBoostPool(uint vid) public view returns (uint, IBoostPool) {
        return boostPoolVid(vid, vaultInfo[vid].numBoosts + 1);
    }

    function boostPoolVid(uint vid, uint16 n) public view returns (uint, IBoostPool) {

        uint _boostID = (uint(bytes32(bytes4(0xB0057000 + n))) | vid);
        return (_boostID, boostPool(_boostID));
    }

    function createBoost(uint vid, address _implementation, bytes calldata initdata) external requireValidVid(vid) onlyRole(BOOST_ADMIN) {
        if (vid >= 2**224) revert MaximizerTooDeep(vid);
        VaultInfo storage vault = vaultInfo[vid];
        uint16 nonce = vault.numBoosts;
        vault.numBoosts = nonce + 1;

        uint _boostID = (uint(bytes32(bytes4(0xB0057000 + nonce))) | vid);

        IBoostPool _boost = IBoostPool(Cavendish.clone(_implementation, bytes32(_boostID)));

        _boost.initialize(msg.sender, _boostID, initdata);
        activeBoosts.set(_boostID);
        emit AddBoost(_boostID);
    }

    //Users can enableBoost to opt-in to a boosted vault
    function enableBoost(address _user, uint _boostID) public nonReentrant {
		
        if (msg.sender != _user && !isApprovedForAll(_user, msg.sender)) revert NotApprovedToEnableBoost(_user, msg.sender);
        if (!activeBoosts.get(_boostID)) revert BoostPoolNotActive(_boostID);
        if (userBoosts[_user].get(_boostID)) revert BoostPoolAlreadyJoined(_user, _boostID);
        userBoosts[_user].set(_boostID);

        boostPool(_boostID).joinPool(_user, uint112(balanceOf(_user, uint224(_boostID))));
        emit EnableBoost(_user, _boostID);
    }

    //Standard opt-in function users will call
    function enableBoost(uint _boostID) external {
        enableBoost(msg.sender, _boostID);
    }

    function harvestBoost(uint _boostID) external nonReentrant {
        boostPool(_boostID).harvest(msg.sender);
    }

    //In case of a buggy boost pool, users can opt out at any time but lose the boost rewards
    function emergencyBoostWithdraw(uint _boostID) external nonReentrant {
        if (!userBoosts[msg.sender].get(_boostID)) revert BoostPoolNotJoined(msg.sender, _boostID);
        try boostPool(_boostID).emergencyWithdraw{gas: 2**19}(msg.sender) returns (bool success) {
            if (!success) activeBoosts.unset(_boostID); //Disable boost if the pool is broken
        } catch {
            activeBoosts.unset(_boostID);
        }
        userBoosts[msg.sender].unset(_boostID);
        emit BoostEmergencyWithdraw(msg.sender, _boostID);
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
        //If boosted pools are affected, update them
        for (uint i; i < ids.length; i++) {
            uint vid = ids[i];
            uint numBoosts = vaultInfo[vid].numBoosts;
            for (uint16 k; k < numBoosts; k++) { //Loop through all of the transferred token's boostpools (if any)
				address _from = from;
				address _to = to;
                (uint boostID, IBoostPool pool) = boostPoolVid(vid, k); //calculate address and ID for pool
                if (_from != address(0) && !userBoosts[_from].get(boostID)) _from = address(0); //Ignore from and to users if they didn't join the pool
                if (_to != address(0) && !userBoosts[_to].get(boostID)) _to = address(0);

            //Send addresses of any users and transfer amounts, but only if they are in the pool
                if ((_from != address(0) || _to != address(0)) && pool.notifyOnTransfer(_from, _to, amounts[i])) {// Is the pool closed?
                    activeBoosts.unset(boostID); //close finished pool
                    if (_to != address(0)) userBoosts[_to].unset(boostID); //pool finished for "to"
                    if (_from != address(0)) userBoosts[_from].unset(boostID); //pool finished for "from"
                }
            }
        }
    }
}

