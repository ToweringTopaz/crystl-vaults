// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./VaultHealerGate.sol";
import "./interfaces/IBoostPool.sol";

abstract contract VaultHealerBoostedPools is VaultHealerGate {
    using BitMaps for BitMaps.BitMap;

    bytes32 public constant BOOSTPOOL = keccak256("BOOSTPOOL");
    bytes32 public constant BOOST_ADMIN = keccak256("BOOST_ADMIN");

    mapping(uint256 => BitMaps.BitMap) activeBoosts;

    event AddBoost(address boost, uint vid, uint boostid);
    event BoostEmergencyWithdraw(address user, uint _vid, uint _boostID);
    
    constructor(address _owner) {
        _setupRole(BOOST_ADMIN, _owner);
        _setRoleAdmin(BOOSTPOOL, BOOST_ADMIN);
    }

    function createVault(address _implementation, bytes calldata data) external returns (uint32 vid) {
        vid = nextVid;
        nextVid = vid + 1;
        Vault.Info storage vault = vaultInfo[vid];

        IStrategy _strat = IStrategy(clone(_implementation, STRATEGY ^ bytes32(uint256(vid))));
        assert(_strat == strat(vid));
        
        _strat.initialize(data);
        
        grantRole(STRATEGY, address(_strat)); //requires msg.sender is VAULT_ADDER
        
        IERC20 want = _strat.wantToken();
        vault.want = want;

        require(want.totalSupply() <= type(uint112).max, "incompatible total supply");
        pauseMap.set(vid); //uninitialized vaults are paused; this unpauses
        
        emit AddVault(vid);
    }

    function createBoost(uint vid, address _implementation, bytes calldata initdata) external requireValidVid(vid) {
        Vault.Info storage vault = vaultInfo[vid];
        uint _boostID = vault.numBoosts;
        vault.numBoosts = _boostID + 1;

        IBoostPool _boost = IBoostPool(clone(_implementation, keccak256(abi.encodePacked(BOOSTPOOL, vid, _boostID))));
        assert(_boost == boost(vid));
        grantRole(BOOSTPOOL, _boost); //requires msg.sender is BOOST_ADMIN

        _boost.initialize(initdata);

        require(vid == IBoostPool(_boost).STAKE_TOKEN_VID(), "VH: boost pool vid mismatch");

        activeBoosts[vid].set(_boostID);

        emit AddBoost(_boost, vid, _boostID);
    }

    //Users can enableBoost to opt-in to a boosted vault
    function enableBoost(address _user, uint _vid, uint _boostID) public nonReentrant {
        require(msg.sender == _user || isApprovedForAll(_user, msg.sender), "VH: must be approved to accept boost");
        Vault.Info storage vault = _vaultInfo[_vid];
        Vault.User storage user = vault.user[_user];
        require(vault.activeBoosts.get(_boostID), "not an active boost");
        require(!user.boosts.get(_boostID), "boost is already active for user");
        user.boosts.set(_boostID);

        vault.boosts[_boostID].joinPool(_user, balanceOf(_user, _vid));
    }

    //Standard opt-in function users will call
    function enableBoost(uint _vid, uint _boostID) external {
        enableBoost(msg.sender, _vid, _boostID);
    }

    function harvestBoost(uint _vid, uint _boostID) external nonReentrant {
        _vaultInfo[_vid].boosts[_boostID].harvest(msg.sender);
    }

    //In case of a buggy boost pool, users can opt out at any time but lose the boost rewards
    function emergencyBoostWithdraw(uint _vid, uint _boostID) external nonReentrant {
        Vault.Info storage vault = _vaultInfo[_vid];
        Vault.User storage user = vault.user[msg.sender];
        IBoostPool boostPool = vault.boosts[_boostID];

        require(user.boosts.get(_boostID), "boost is not active for user");
        try boostPool.emergencyWithdraw{gas: 500000}(msg.sender) returns (bool success) {
            if (!success) vault.activeBoosts.unset(_boostID); //Disable boost if the pool is broken
        } catch {
            vault.activeBoosts.unset(_boostID);
        }
        user.boosts.unset(_boostID);
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
            Vault.Info storage vault = _vaultInfo[ids[i]];
            for (uint k; k < vault.boosts.length; k++) {
                bool fromBoosted = from != address(0) && vault.user[from].boosts.get(k);
                bool toBoosted = to != address(0) && vault.user[to].boosts.get(k);

                if (!fromBoosted && !toBoosted) continue;
                IBoostPool boostPool = vault.boosts[k];

                uint status = boostPool.notifyOnTransfer(
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

