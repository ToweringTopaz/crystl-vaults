// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "../interfaces/IBoostPool.sol";
import "../interfaces/IUniFactory.sol";
import "../interfaces/IMagnetite.sol";
import "../interfaces/IUniRouter.sol";
import "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import "./Tactics.sol";

library Vault {
    
    struct Info {
        uint40 panicLockExpiry; //panic can only happen again after the time has elapsed
        IERC20 want;
        uint112 wantLockedLastUpdate;
        uint32 lastEarnBlock;
        uint32 targetVid; //maximizer target, which accumulates tokens
        IBoostPool[] boosts;
        BitMaps.BitMap activeBoosts;
        mapping (address => User) user;

        uint256 accRewardTokensPerShare;
        uint256 balanceCrystlCompounderLastUpdate;
        
    }
    struct User {
        BitMaps.BitMap boosts;
        uint256 rewardDebt;
    }
}