// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./IUniRouter.sol";
import "./IMagnetite.sol";

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

library LibVaultConfig {
    
    uint256 constant FEE_MAX_TOTAL = 10000; //hard-coded maximum fee (100%)
    uint256 constant FEE_MAX = 10000; // 100 = 1% : basis points
    uint256 constant SLIPPAGE_FACTOR_UL = 9950; // Must allow for at least 0.5% slippage (rounding errors)
    
    function check(VaultFees memory _fees) internal pure {
        require(_fees.treasuryFee.receiver != address(0) || _fees.treasuryFee.rate == 0, "Invalid treasury address");
        require(_fees.burn.receiver != address(0) || _fees.treasuryFee.rate == 0, "Invalid buyback address");
        require(_fees.userReward.rate + _fees.treasuryFee.rate + _fees.burn.rate <= FEE_MAX_TOTAL, "Max fee of 100%");
    }

    function check(VaultFee memory _fee) internal pure {
        if (_fee.rate > 0) {
            require(_fee.receiver != address(0), "Invalid treasury address");
            require(_fee.rate <= FEE_MAX_TOTAL, "Max fee of 100%");
        }
    }

    function check(VaultSettings memory _settings) internal pure {
        try IUniRouter(_settings.router).factory() returns (address) {}
        catch { revert("Invalid router"); }
        require(_settings.slippageFactor <= SLIPPAGE_FACTOR_UL, "_slippageFactor too high");
    }

    
}