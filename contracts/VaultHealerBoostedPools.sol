// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./VaultHealerGate.sol";
import "./interfaces/IBoostPool.sol";

abstract contract VaultHealerBoostedPools is VaultHealerGate {
    using BitMaps for BitMaps.BitMap;

    bytes32 public constant BOOSTPOOL = keccak256("BOOSTPOOL");
    bytes32 public constant BOOST_ADMIN = keccak256("BOOST_ADMIN");

    BitMaps.BitMap activeBoosts;
    mapping(address => BitMaps.BitMap) userBoosts;

    event AddBoost(uint indexed boostid);
    event BoostEmergencyWithdraw(address user, uint _boostID);
    
    constructor(address _owner) {
        _setupRole(BOOST_ADMIN, _owner);
        _setRoleAdmin(BOOSTPOOL, BOOST_ADMIN);
    }
    function boostPool(uint _boostID) public view returns (IBoostPool) {
        return IBoostPool(Cavendish.computeAddress(BOOSTPOOL ^ bytes32(_boostID)));
    }

    function createBoost(uint vid, address _implementation, bytes calldata initdata) external requireValidVid(vid) {
        VaultInfo storage vault = vaultInfo[vid];
        uint32 nonce = vault.numBoosts;
        vault.numBoosts = nonce + 1;
        uint _boostID = (uint(nonce) << 224) | vid;

        IBoostPool _boost = IBoostPool(clone(_implementation, BOOSTPOOL ^ bytes32(_boostID)));
        assert(_boost == boostPool(_boostID));
        grantRole(BOOSTPOOL, address(_boost)); //requires msg.sender is BOOST_ADMIN

        _boost.initialize(msg.sender, _boostID, initdata);

        activeBoosts.set(_boostID);

        emit AddBoost(_boostID);
    }

    //Users can enableBoost to opt-in to a boosted vault
    function enableBoost(address _user, uint _boostID) public nonReentrant {
        require(msg.sender == _user || isApprovedForAll(_user, msg.sender), "VH: must be approved to accept boost");
        require(activeBoosts.get(_boostID), "not an active boost");
        require(!userBoosts[_user].get(_boostID), "boost is already active for user");
        userBoosts[_user].set(_boostID);

        boostPool(_boostID).joinPool(_user, uint112(balanceOf(_user, uint224(_boostID))));
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
        require(userBoosts[msg.sender].get(_boostID), "boost is not active for user");
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
            VaultInfo storage vault = vaultInfo[ids[i]];
            uint numBoosts = vault.numBoosts;
            for (uint k; k < numBoosts; k++) {
                bool fromBoosted = from != address(0) && userBoosts[from].get(k);
                bool toBoosted = to != address(0) && userBoosts[to].get(k);

                if (!fromBoosted && !toBoosted) continue;

                uint status = boostPool((k << 224) | ids[i]).notifyOnTransfer(
                    fromBoosted ? from : address(0),
                    toBoosted ? to : address(0),
                    uint112(amounts[i])
                );

                if (status & 1 > 0) { //pool finished for "from"
                    userBoosts[from].unset(k);
                }
                if (status & 2 > 0) { //pool finished for "to"
                    userBoosts[to].unset(k);
                }
                if (status & 4 > 0) { //close finished pool
                    activeBoosts.unset(k);
                }
            }
        }
    }


}

