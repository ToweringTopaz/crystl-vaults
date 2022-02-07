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
        uint32 numMaximizers; //number of maximizer vaults pointing here. If this is vid 0x00000045, its first maximizer will be 0x0000004500000000
        uint32 targetVid; //maximizer target, which accumulates tokens. Zero for standard strategies compounding their own want token
        IBoostPool[] boosts;
        BitMaps.BitMap activeBoosts;
    }
    struct User {
        BitMaps.BitMap boosts;
        BitMaps.BitMap maximizers;
    }
}