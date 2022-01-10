// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import {IERC20Upgradeable as IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./IBoostPool.sol";
import "./IUniFactory.sol";
import "./IMagnetite.sol";
import "./IUniRouter.sol";
import {BitMapsUpgradeable as BitMaps} from "@openzeppelin/contracts-upgradeable/utils/structs/BitMapsUpgradeable.sol";

library Vault {

    type Fee is uint176;
    uint16 constant FEE_MAX = 10000;

    struct Info {
        IERC20 want; //  want token.
        //IUniRouter router;
        Fee withdrawFee;
        Fee[] earnFees;
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

    function rate(Fee _fee) internal pure returns (uint16) {
        return uint16(Fee.unwrap(_fee));
    }
    function receiver(Fee _fee) internal pure returns (address) {
        return address(uint160(Fee.unwrap(_fee) >> 16));
    }
    function receiverAndRate(Fee _fee) internal pure returns (address, uint16) {
        uint fee = Fee.unwrap(_fee);
        return (address(uint160(fee >> 16)), uint16(fee));
    }
    function createFee(address _receiver, uint16 _rate) internal pure returns (Fee) {
        return Fee.wrap(uint176(uint160(_receiver)) | _rate);
    }

    function set(Fee[] storage _fees, address[] memory _receivers, uint16[] memory _rates) internal {
        uint len = _receivers.length;
        require(_rates.length == len);
        
        uint oldLen = _fees.length; 
        for (uint i = len; i < oldLen; i++) {
            _fees.pop();
        }

        uint feeTotal;
        for (uint i; i < len; i++) {
            address _receiver = _receivers[i];
            uint16 _rate = _rates[i];
            require(_receiver != address(0) && _rate != 0);
            feeTotal += _rate;
            uint176 _fee = uint176(uint160(_receiver)) << 16 | _rate;
            if (_fees.length < len) _fees.push();
            _fees[i] = Fee.wrap(_fee);
        }
        require(feeTotal <= FEE_MAX, "Max total fee of 100%");
    }

    uint256 constant SLIPPAGE_FACTOR_UL = 9950; // Must allow for at least 0.5% slippage (rounding errors)

    function check(Settings memory _settings) internal pure {
        try _settings.router.factory() returns (IUniFactory) {}
        catch { revert("Invalid router"); }
        require(_settings.slippageFactor <= SLIPPAGE_FACTOR_UL, "_slippageFactor too high");
    }

    
}