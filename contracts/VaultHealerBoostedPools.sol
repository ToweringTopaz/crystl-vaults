// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./VaultHealerGate.sol";

abstract contract VaultHealerBoostedPools is VaultHealerGate {
    using BitMaps for BitMaps.BitMap;

    bytes32 public constant BOOSTPOOL = keccak256("BOOSTPOOL");
    bytes32 public constant BOOST_ADMIN = keccak256("BOOST_ADMIN");

    event AddBoost(IBoostPool boost, uint vid, uint boostid);
    event BoostEmergencyWithdraw(address user, uint _vid, uint _boostID);
    
    constructor(address _owner) {
        _setupRole(BOOST_ADMIN, _owner);
        _setRoleAdmin(BOOSTPOOL, BOOST_ADMIN);
    }

    function addBoost(IBoostPool _boost) external {
        grantRole(BOOSTPOOL, address(_boost)); //requires msg.sender is BOOST_ADMIN
        require(block.number < _boost.bonusEndBlock(), "boost pool already ended");

        uint vid = _boost.STAKE_TOKEN_VID();
        VaultInfo storage vault = _vaultInfo[vid];
        uint boostID = vault.boosts.length;

        _boost.vaultHealerActivate(boostID);

        
        vault.boosts.push() = _boost;
        vault.activeBoosts.set(boostID);

        emit AddBoost(_boost, vid, boostID);
    }

    //Users can enableBoost to opt-in to a boosted vault
    function _enableBoost(address _user, uint _vid, uint _boostID) internal {
        VaultInfo storage vault = _vaultInfo[_vid];
        BitMaps.BitMap storage userBoosts = vault.userBoosts[_user];
        require(vault.activeBoosts.get(_boostID), "not an active boost");
        require(!vault.userBoosts.get(_boostID), "boost is already active for user");

        userBoosts.set(_boostID);

        vault.boosts[_boostID].boostPool.joinPool(_user, balanceOf(_user, _vid));
    }
    //To opt-in an account other than the user's; needs approval
    function enableBoost(address _user, uint _vid, uint _boostID) external nonReentrant {
        require(isApprovedForAll(_user, _msgSender()) || _msgSender() == _user, "VH: must be approved to accept boost");
        _enableBoost(_user, _vid, _boostID);
    }
    //Standard opt-in function users will call
    function enableBoost(uint _vid, uint _boostID) external nonReentrant {
        _enableBoost(_msgSender(), _vid, _boostID);
    }

    function harvestBoost(uint _vid, uint _boostID) external nonReentrant {
        _vaultInfo[_vid].boosts[_boostID].harvest(msg.sender);
    }

    //In case of a buggy boost pool, users can opt out at any time but lose the boost rewards
    function emergencyBoostWithdraw(uint _vid, uint _boostID) external nonReentrant {
        VaultInfo storage vault = _vaultInfo[_vid];
        BitMaps.BitMap storage userBoosts = vault.userBoosts[msg.sender];
        IBoostPool boost = vault.boosts[_boostID];

        require(userBoosts.get(_boostID), "boost is not active for user");
        try boost.emergencyWithdraw{gas: 500000}(_msgSender()) returns (bool success) {
            if (!success) vault.activeBoosts.unset(_boostID); //Disable boost if the pool is broken
        } catch {
            vault.activeBoosts.unset(_boostID); //Disable boost if the pool is broken
        }
        userBoosts.unset(_boostID);
        emit BoostEmergencyWithdraw(msg.sender, _vid, _boostID);
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
            VaultInfo storage vault = _vaultInfo[i];

            for (uint k; k < _vaultInfo[i].boosts.length; k++) {
                IBoostPool boost = vault.boosts[k];
                bool fromBoosted = from != address(0) && vault.user[from].boosts.get(k);
                bool toBoosted = to != address(0) && vault.user[to].boosts.get(k);

                if (!fromBoosted && !toBoosted) continue;

                uint status = boost.notifyOnTransfer(
                    fromBoosted ? from : address(0),
                    toBoosted ? to : address(0),
                    amounts[i]
                );

                if (status & 1 > 0) { //pool finished for "from"
                    vault.user[from].boosts.unset(k);
                }
                if (status & 2 > 0) { //pool finished for "to"
                    vault.user[to].boosts.unset(k);
                }
                if (status & 4 > 0) { //close finished pool
                    vault.activeBoosts.unset(k);
                }
            }
        }
    }


}

