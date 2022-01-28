// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import {IERC20Upgradeable as IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./IBoostPool.sol";
import "./IUniFactory.sol";
import "./IMagnetite.sol";
import "./IUniRouter.sol";
import {BitMapsUpgradeable as BitMaps} from "@openzeppelin/contracts-upgradeable/utils/structs/BitMapsUpgradeable.sol";
import "./Tactics.sol";

library Vault {
    
    struct Info {
        IERC20 want; //  want token.
        //IUniRouter router;
        IBoostPool[] boosts;
        BitMaps.BitMap activeBoosts;
        mapping (address => User) user;
        uint256 accRewardTokensPerShare;
        uint256 balanceCrystlCompounderLastUpdate;
        uint32 targetVid; //maximizer target, which accumulates tokens

        uint112 wantLockedLastUpdate;
        uint112 totalDepositsLastUpdate;
        uint32 lastEarnBlock;
        uint32 minBlocksBetweenEarns; //Prevents token waste, exploits and unnecessary reverts
        uint40 panicLockExpiry; //panic can only happen again after the time has elapsed
        // bytes data;
    }

    struct User {
        BitMaps.BitMap boosts;
        uint256 rewardDebt;
        TransferData stats;
    }

    struct TransferData { //All stats in underlying want tokens
        uint128 deposits;
        uint128 withdrawals;
        uint128 transfersIn;
        uint128 transfersOut;
    }

}