// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import "./VaultHealerGate.sol";
import "./libs/IBoostPool.sol";

abstract contract VaultHealerBoostedPools is VaultHealerGate {
    using BitMaps for BitMaps.BitMap;

    event AddBoost(address boost, uint pid, uint boostid);
    event BoostEmergencyWithdraw(address user, uint _pid, uint _boostID);
    


    function addBoost(address _boost) external {
        require(!hasRole(BOOSTPOOL, _boost), "boost pool already added");
        grantRole(BOOSTPOOL, _boost); //requires msg.sender is BOOST_ADMIN
        require(block.number < IBoostPool(_boost).bonusEndBlock(), "boost pool already ended");


        uint pid = IBoostPool(_boost).STAKE_TOKEN_PID();
        PoolInfo storage vault = _poolInfo[pid];

        IBoostPool(_boost).vaultHealerActivate(vault.boosts.length);

        vault.boosts.push() = BoostInfo({
            boostPool: IBoostPool(_boost),
            isActive: true
        });
        emit AddBoost(_boost, pid, vault.boosts.length - 1);
    }

    //Users can enableBoost to opt-in to a boosted vault
    function _enableBoost(address _user, uint _pid, uint _boostID) internal {
        PoolInfo storage vault = _poolInfo[_pid];
        UserInfo storage user = vault.user[_user];
        require(vault.boosts[_boostID].isActive, "not an active boost");
        require(user.boosts.get(_boostID), "boost is already active for user");

        user.boosts.set(_boostID);

        vault.boosts[_boostID].boostPool.joinPool(_user, balanceOf(_user, _pid));
    }
    //To opt-in an account other than the user's; needs approval
    function enableBoost(address _user, uint _pid, uint _boostID) external {
        require(isApprovedForAll(_user, _msgSender()) || _msgSender() == _user, "VH: must be approved to accept boost");
        _enableBoost(_user, _pid, _boostID);
    }
    //Standard opt-in function users will call
    function enableBoost(uint _pid, uint _boostID) external {
        _enableBoost(_msgSender(), _pid, _boostID);
    }

    function boostShares(address _user, uint _pid, uint _boostID) external view returns (uint) {
        PoolInfo storage vault = _poolInfo[_pid];
        UserInfo storage user = vault.user[_user];
        if (user.boosts.get(_boostID)) return 0;
        return balanceOf(_user, _pid);
    }

    //In case of a buggy boost pool, users can opt out at any time but lose the boost rewards
    function emergencyBoostWithdraw(uint _pid, uint _boostID) external {
        PoolInfo storage vault = _poolInfo[_pid];
        UserInfo storage user = vault.user[msg.sender];
        BoostInfo storage boost = vault.boosts[_boostID];

        require(user.boosts.get(_boostID), "boost is not active for user");
        try boost.boostPool.emergencyWithdraw{gas: 500000}(_msgSender()) returns (bool success) {
            if (!success) boost.isActive = false; //Disable boost if the pool is broken
        } catch {
            boost.isActive = false;
        }
        user.boosts.unset(_boostID);
        emit BoostEmergencyWithdraw(msg.sender, _pid, _boostID);
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
            PoolInfo storage vault = _poolInfo[i];

            for (uint k; k < _poolInfo[i].boosts.length; k++) {
                BoostInfo storage boost = vault.boosts[k];
                bool fromBoosted = from != address(0) && vault.user[from].boosts.get(k);
                bool toBoosted = to != address(0) && vault.user[to].boosts.get(k);

                if (!fromBoosted && !toBoosted) continue;

                uint status = boost.boostPool.notifyOnTransfer(
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
                    boost.isActive = false;
                }
            }
        }
    }


}

