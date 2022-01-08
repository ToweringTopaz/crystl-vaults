// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IStrategy.sol";
import "../BoostPool.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

struct VaultInfo {
    IERC20 want; //  want token.
    //IUniRouter router;
    VaultFee withdrawFee;
    VaultFees earnFees;
    BoostInfo[] boosts;
    mapping (address => UserInfo) user;
    uint256 accRewardTokensPerShare;
    uint256 balanceCrystlCompounderLastUpdate;
    uint256 targetVid; //maximizer target, which accumulates tokens
    uint256 panicLockExpiry; //panic can only happen again after the time has elapsed
    uint256 lastEarnBlock;
    uint256 minBlocksBetweenEarns; //Prevents token waste, exploits and unnecessary reverts
    // bytes data;
}

struct BoostInfo {
    BoostPool boostPool;
    bool isActive;
}

struct UserInfo {
    BitMaps.BitMap boosts;
    uint256 rewardDebt;
}

struct VaultSettings {
    IUniRouter router; //UniswapV2 compatible router
    uint16 slippageFactor; // sets a limit on losses due to deposit fee in pool, reflect fees, rounding errors, etc.
    uint16 tolerance; // "Hidden Gem", "Premiere Gem", etc. frontend indicator
    uint64 minBlocksBetweenEarns; //Prevents token waste, exploits and unnecessary reverts
    uint88 dust; //min token amount to swap/deposit. Prevents token waste, exploits and unnecessary reverts
    bool feeOnTransfer;
    IMagnetite magnetite;
}

struct VaultFees {
    VaultFee userReward; //rate paid to user who called earn()
    VaultFee treasuryFee; //fees that get paid to the crystl.finance treasury
    VaultFee burn; //burn address for CRYSTL
}
struct VaultFee {
    address receiver;
    uint16 rate;
}