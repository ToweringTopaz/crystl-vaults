// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./IMagnetite.sol";
import "./ITactic.sol";

struct VaultSettings {
    IMagnetite magnetite;
    uint96 dust; //min token amount to swap/deposit. Prevents token waste, exploits and unnecessary reverts
    IUniRouter router; //UniswapV2 compatible router
    uint16 minBlocksBetweenEarns; //Prevents token waste, exploits and unnecessary reverts
    uint16 slippageFactorSwap; // sets a limit on losses due to deposit fee in pool, reflect fees, rounding errors, etc.
    uint16 slippageFactorFarm;
    uint16 slippageFactorWithdraw;
    bool feeOnTransfer;
}

struct VaultConfig {
    IERC20 wantToken;
    IERC20[2] lpToken;
    IERC20[8] earned;
    
    address masterchef;
    uint pid;
    ITactic tactic;
}

enum VaultStatus { NORMAL, PAUSED, PANIC, TESTING, PAUSED_TESTING, PANIC_TESTING, DEAD }

struct VaultWithdrawData {
    uint96 dust; //min token amount to swap/deposit. Prevents token waste, exploits and unnecessary reverts
    uint16 slippageFactorWithdraw;
    VaultStatus status; // will be one of NORMAL, PAUSED, PANIC here
    uint112 wantAmt;
}

function check(VaultSettings memory _settings) pure {
    uint SLIPPAGE_FACTOR_UL_SWAP = 9950; // Must allow for at least 0.5% slippage (rounding errors)
    uint SLIPPAGE_FACTOR_UL_FARM = 9999;
    uint SLIPPAGE_FACTOR_UL_WITHDRAW = 9999;

    try _settings.router.factory() returns (IUniFactory) {}
    catch { revert("Invalid router"); }
    require(_settings.slippageFactorSwap <= SLIPPAGE_FACTOR_UL_SWAP, "_slippageFactorSwap too high");
    require(_settings.slippageFactorFarm <= SLIPPAGE_FACTOR_UL_FARM, "_slippageFactorFarm too high");
    require(_settings.slippageFactorWithdraw <= SLIPPAGE_FACTOR_UL_WITHDRAW, "_slippageFactorWithdraw too high");
}

