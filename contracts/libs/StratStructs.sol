// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

address constant DAI = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
address constant CRYSTL = 0x76bF0C28e604CC3fE9967c83b3C3F31c213cfE64;
address constant WNATIVE = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
uint256 constant FEE_MAX_TOTAL = 10000;
uint256 constant FEE_MAX = 10000; // 100 = 1%
uint256 constant WITHDRAW_FEE_FACTOR_MAX = 10000;
uint256 constant WITHDRAW_FEE_FACTOR_LL = 9900;
uint256 constant SLIPPAGE_FACTOR_UL = 9950;
uint256 constant MAX_EXPORTS = 16;

struct Addresses {
    address vaulthealer;
    address router;
    address masterchef;
    address rewardFee;
    address withdrawFee;
    address buybackFee;
    address want;
    address[8] earned;
    address[8] lpToken;
}
struct Settings {
    uint16 controllerFee;
    uint16 rewardRate;
    uint16 buybackRate;
    uint256 withdrawFeeFactor;
    uint256 slippageFactor;
    uint256 tolerance;
    bool feeOnTransfer;
    uint256 dust; //minimum raw token value considered to be worth swapping or depositing
    uint256 minBlocksBetweenSwaps;
}
//Traditional strategies only use shares. Due to how mappings/storage pointers work, the rest can be safely ignored if not relevant to a
//particular strategy
struct UserInfo {
    uint256 shares; // How many LP tokens the user has provided.
}

struct ExportInfo {
    address strat;
    uint accCoreShares;
    uint totalXShares;
    mapping(address => UserExportInfo) user;
}
struct UserExportInfo {
    uint256 xShares; //tokens which do not auto-compound but instead export their earnings
    uint256 coreShareDebt;
}