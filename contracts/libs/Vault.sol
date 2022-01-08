// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import {IERC20Upgradeable as IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./IBoostPool.sol";
import "./IUniFactory.sol";
import "./IMagnetite.sol";
import "./IUniRouter.sol";
import {BitMapsUpgradeable as BitMaps} from "@openzeppelin/contracts-upgradeable/utils/structs/BitMapsUpgradeable.sol";

library Vault {
    
    struct Info {
        IERC20 want; //  want token.
        //IUniRouter router;
        Fee withdrawFee;
        Fees earnFees;
        IBoostPool[] boosts;
        BitMaps.BitMap activeBoosts;
        mapping (address => User) user;
        uint256 accRewardTokensPerShare;
        uint256 balanceCrystlCompounderLastUpdate;
        uint256 targetVid; //maximizer target, which accumulates tokens
        uint256 panicLockExpiry; //panic can only happen again after the time has elapsed
        uint256 lastEarnBlock;
        uint256 minBlocksBetweenEarns; //Prevents token waste, exploits and unnecessary reverts
        // bytes data;
    }

    struct User {
        BitMaps.BitMap boosts;
        uint256 rewardDebt;
    }

    struct Settings {
        IUniRouter router; //UniswapV2 compatible router
        uint16 slippageFactor; // sets a limit on losses due to deposit fee in pool, reflect fees, rounding errors, etc.
        uint16 tolerance; // "Hidden Gem", "Premiere Gem", etc. frontend indicator
        uint64 minBlocksBetweenEarns; //Prevents token waste, exploits and unnecessary reverts
        uint88 dust; //min token amount to swap/deposit. Prevents token waste, exploits and unnecessary reverts
        bool feeOnTransfer;
        IMagnetite magnetite;
    }

    struct Fees {
        Fee userReward; //rate paid to user who called earn()
        Fee treasuryFee; //fees that get paid to the crystl.finance treasury
        Fee burn; //burn address for CRYSTL
    }
    struct Fee {
        address receiver;
        uint16 rate;
    }

    uint256 constant FEE_MAX_TOTAL = 10000; //hard-coded maximum fee (100%)
    uint256 constant FEE_MAX = 10000; // 100 = 1% : basis points
    uint256 constant SLIPPAGE_FACTOR_UL = 9950; // Must allow for at least 0.5% slippage (rounding errors)
    
    function check(Fees memory _fees) internal pure {
        require(_fees.treasuryFee.receiver != address(0) || _fees.treasuryFee.rate == 0, "Invalid treasury address");
        require(_fees.burn.receiver != address(0) || _fees.treasuryFee.rate == 0, "Invalid buyback address");
        require(_fees.userReward.rate + _fees.treasuryFee.rate + _fees.burn.rate <= FEE_MAX_TOTAL, "Max fee of 100%");
    }

    function check(Fee memory _fee) internal pure {
        if (_fee.rate > 0) {
            require(_fee.receiver != address(0), "Invalid treasury address");
            require(_fee.rate <= FEE_MAX_TOTAL, "Max fee of 100%");
        }
    }

    function check(Settings memory _settings) internal pure {
        try _settings.router.factory() returns (IUniFactory) {}
        catch { revert("Invalid router"); }
        require(_settings.slippageFactor <= SLIPPAGE_FACTOR_UL, "_slippageFactor too high");
    }

    
}