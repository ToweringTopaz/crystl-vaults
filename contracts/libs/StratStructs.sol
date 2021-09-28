// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

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