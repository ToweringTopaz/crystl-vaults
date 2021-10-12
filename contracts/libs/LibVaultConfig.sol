// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./IUniRouter.sol";
import "../Magnetite.sol";

struct VaultSettings {
    IUniRouter02 router; //UniswapV2 compatible router
    uint16 slippageFactor; // sets a limit on losses due to deposit fee in pool, reflect fees, rounding errors, etc.
    uint16 tolerance; // "Hidden Gem", "Premiere Gem", etc. frontend indicator
    uint64 minBlocksBetweenEarns; //Prevents token waste, exploits and unnecessary reverts
    uint88 dust; //min token amount to swap/deposit. Prevents token waste, exploits and unnecessary reverts
    bool feeOnTransfer;
    Magnetite magnetite;
}

struct VaultFees {
    VaultFee withdraw;
    VaultFee earn; //rate paid to user who called earn()
    VaultFee reward; //"reward" fees on earnings are sent here
    VaultFee burn; //burn address for CRYSTL
}
struct VaultFee {
    IERC20 token;
    address receiver;
    uint96 rate;
}

library LibVaultConfig {
    
    uint256 constant FEE_MAX_TOTAL = 10000; //hard-coded maximum fee (100%)
    uint256 constant FEE_MAX = 10000; // 100 = 1% : basis points
    uint256 constant WITHDRAW_FEE_MAX = 100; // means 1% withdraw fee maximum
    uint256 constant WITHDRAW_FEE_LL = 0; //means 0% withdraw fee minimum
    uint256 constant SLIPPAGE_FACTOR_UL = 9950; // Must allow for at least 0.5% slippage (rounding errors)
    
    function check(VaultFees memory _fees) external pure {
        
        require(_fees.reward.receiver != address(0), "Invalid reward address");
        require(_fees.burn.receiver != address(0), "Invalid buyback address");
        require(_fees.earn.rate + _fees.reward.rate + _fees.burn.rate <= FEE_MAX_TOTAL, "Max fee of 100%");
        require(_fees.withdraw.rate >= WITHDRAW_FEE_LL, "_withdrawFeeFactor too low");
        require(_fees.withdraw.rate <= WITHDRAW_FEE_MAX, "_withdrawFeeFactor too high");
    }
    
    function check(VaultSettings memory _settings) external pure {
        try IUniRouter02(_settings.router).factory() returns (address) {}
        catch { revert("Invalid router"); }
        require(_settings.slippageFactor <= SLIPPAGE_FACTOR_UL, "_slippageFactor too high");
    }
    
}