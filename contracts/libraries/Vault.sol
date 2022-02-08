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
        IERC20 want;
        uint32 lastEarnBlock;
        uint32 panicLockExpiry; //panic can only happen again after the time has elapsed
        uint32 numBoosts;

        uint112 wantLockedLastUpdate;
        uint112 totalMaximizerEarningsOffset;
        uint32 numMaximizers; //number of maximizer vaults pointing here. If this is vid 0x00000045, its first maximizer will be 0x0000004500000000
    }
    struct User {
        BitMaps.BitMap boosts;
        BitMaps.BitMap maximizers;
        uint112 maximizerEarningsOffset;

    }
}