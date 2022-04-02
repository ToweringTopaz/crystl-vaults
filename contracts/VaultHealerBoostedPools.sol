// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import "./VaultHealerGate.sol";
import "./interfaces/IBoostPool.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

abstract contract VaultHealerBoostedPools is VaultHealerGate {
    using BitMaps for BitMaps.BitMap;

    BitMaps.BitMap activeBoosts;
    mapping(address => BitMaps.BitMap) userBoosts;
    
    function boostPool(uint _boostID) public view returns (IBoostPool) {
        return IBoostPool(Cavendish.computeAddress(bytes32(_boostID)));
    }
    
    function nextBoostPool(uint vid) external view returns (uint, IBoostPool) {
        return boostPoolVid(vid, vaultInfo[vid].numBoosts + 1);
    }

    function boostPoolVid(uint vid, uint16 n) public view returns (uint, IBoostPool) {

        uint _boostID = (uint(bytes32(bytes4(0xB0057000 + n))) | vid);
        return (_boostID, boostPool(_boostID));
    }

    function createBoost(uint vid, address _implementation, bytes calldata initdata) external requireValidVid(vid) auth {
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
                updateBoostPool(vid, k, from, to, amounts[i]);
            }
        }
        
    }

    function updateBoostPool(uint vid, uint16 n, address from, address to, uint amount) private {
        (uint boostID, IBoostPool pool) = boostPoolVid(vid, n); //calculate address and ID for pool
        from = from == address(0) || userBoosts[from].get(boostID) ? from : address(0);
        to = to == address(0) || userBoosts[to].get(boostID) ? to : address(0);

        if ((from != address(0) || to != address(0)) && pool.notifyOnTransfer(from, to, amount)) {// Is the pool closed?
            activeBoosts.unset(boostID); //close finished pool
            userBoosts[from].unset(boostID); //pool finished for "from"
            userBoosts[to].unset(boostID); //pool finished for "to"
        }
    }

    struct BoostInfo {
        uint id;
        IERC20 rewardToken;
        uint pendingReward;
    }

    function boostInfo(address account, uint vid) external view returns (
        BoostInfo[] memory active,
        BoostInfo[] memory finished,
        BoostInfo[] memory available
    ) {
        uint16 len = vaultInfo[vid].numBoosts; //total number of boost pools that ever existed for this vault

        //Create bytes array indicating status of each boost pool and total number for each status
        bytes memory statuses = new bytes(len);
        uint numActive;
        uint numFinished;
        uint numAvailable;
        for (uint16 i; i < len; i++) {
            uint id = uint(bytes32(bytes4(0xB0057000 + i))) | vid;
            bytes1 status;

            if (userBoosts[account].get(id)) status = 0x01; //pool active for user
            if (activeBoosts.get(id)) status |= 0x02; //pool still paying rewards
            
            if (status == 0x00) continue; //pool finished, user isn't in, nothing to do
            else if (status == 0x01) numFinished++; //user in finished pool
            else if (status == 0x02) numAvailable++; //user not in active pool
            else numActive++; //user in active pool

            statuses[i] = status;
        }

        active = new BoostInfo[](numActive);
        finished = new BoostInfo[](numFinished);
        available = new BoostInfo[](numAvailable);

        uint activeIndex;
        uint finishedIndex;
        uint availableIndex;

        for (uint16 i; i < len; i++) {
            bytes1 status = statuses[i];
            if (status == 0x00) continue; //pool is done and user isn't in

            (uint boostID, IBoostPool pool) = boostPoolVid(vid, i);

            BoostInfo memory info; //reference to the output array member where we will be storing the data
            if (status == 0x01) {
                info = finished[finishedIndex];
                finishedIndex++;
            }
            else if (status == 0x02) {
                info = available[availableIndex];
                availableIndex++;
            }
            else {
                info = active[activeIndex];
                activeIndex++;
            }

            info.id = boostID;
            (info.rewardToken, info.pendingReward) = pool.pendingReward(account);
        }
    }

}

