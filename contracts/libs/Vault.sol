// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./IBoostPool.sol";
import "./IUniFactory.sol";
import "./IMagnetite.sol";
import "./IUniRouter.sol";
import "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import "./Tactics.sol";

library Vault {
    
    enum Access { NULL, STRATEGY, IMPLEMENTATION, TESTER, PAUSER, ADMIN, OWNER }
    struct Info {
        Access access;
        bool unpaused;
        uint40 panicLockExpiry; //panic can only happen again after the time has elapsed

        IBoostPool[] boosts;
        BitMaps.BitMap activeBoosts;
        mapping (address => User) user;
        uint256 accRewardTokensPerShare;
        uint256 balanceCrystlCompounderLastUpdate;
        uint256 targetVid; //maximizer target, which accumulates tokens
    }
    struct User {
        BitMaps.BitMap boosts;
        uint256 rewardDebt;
    }
}