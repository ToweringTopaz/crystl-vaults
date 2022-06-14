// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "./Tactics.sol";
import "../interfaces/IUniRouter.sol";
import "../interfaces/IMagnetite.sol";
import "../interfaces/IVaultHealer.sol";

library StrategyConfig2 {
    using StrategyConfig2 for MemPointer;
    using Tactics for bytes32[3];

    struct ConfigPacked {

        uint256 vid;
        address router;
        address[8] addresses;
        bytes32[3] tactics;
        uint16 wantOffset;
        uint8 wantDust;
        uint8 numEarned;
        uint16[4] earnedOffset;
        uint8[4] earnedDust;
    }

    struct ConfigUnpacked {

        IERC20 wantToken;
        uint wantDust;
        IERC20
        Tactics.TacticalData tactics;

    }

    struct TokenInfo {
        IERC20 token;
        uint256 dust;
        bool isLP;
        bool isEarned;
        bool isWant;
        bool is
    }

    type MemPointer is uint256;

    uint constant MASK_160 = 0x00ffffffffffffffffffffffffffffffffffffffff;

    function vid(MemPointer config) internal pure returns (uint256 _vid) {
        assembly ("memory-safe") {
            _vid := mload(config)
        }
    }
    function targetVid(MemPointer config) internal pure returns (uint256 _targetVid) {
        assembly ("memory-safe") {
            _targetVid := shr(0x10, mload(config))
        }
    }
    function isMaximizer(MemPointer config) internal pure returns (bool _isMaximizer) {
        assembly ("memory-safe") {
            _isMaximizer := gt(shr(0x10, mload(config)), 0)
        }
    }

    function tactics(MemPointer config) internal pure returns (bytes32[3] memory _tactics) {
        assembly {
            _tactics := add(config, 0x20)
        }
    }
    function wantToken(MemPointer config) internal pure returns (IERC20 want) {
        assembly ("memory-safe") {
            want := and(mload(add(config,0x74)), MASK_160)
        }
    }
    function wantDust(MemPointer config) internal pure returns (uint256 dust) {
        assembly ("memory-safe") {
            dust := shl(and(mload(add(config,0x75)), 0xff),1)
        }
    }
    function router(MemPointer config) internal pure returns (IUniRouter _router) {
        assembly ("memory-safe") {
            _router := and(mload(add(config,0x89)), MASK_160)
        }
    }
    function magnetite(MemPointer config) internal pure returns (IMagnetite _magnetite) {
        assembly ("memory-safe") {
            _magnetite := and(mload(add(config,0x9D)), MASK_160)
        }        
    }
    function slippageFactor(MemPointer config) internal pure returns (uint _factor) {
        assembly ("memory-safe") {
            _factor := and(mload(add(config,0x9E)), 0xff)
        }
    }
    function feeOnTransfer(MemPointer config) internal pure returns (bool _isFeeOnTransfer) {
        assembly ("memory-safe") {
            _isFeeOnTransfer := gt(and(mload(add(config,0x9F)), 0x80), 0)
        }
    }

    function isMetaVault(MemPointer config) internal pure returns (bool _isMetaVault) {
        assembly ("memory-safe") {
            _isMetaVault := gt(and(mload(add(config,0x9F)), 0x40), 0)
        }
    }

    function isPairStake(MemPointer config) internal pure returns (bool _isPairStake) {
        assembly ("memory-safe") {
            _isPairStake := gt(and(mload(add(config,0x9F)), 0x20), 0)
        }
    }
    function earnedLength(MemPointer config) internal pure returns (uint _earnedLength) {
        assembly ("memory-safe") {
            _earnedLength := and(mload(add(config,0x9F)), 0x1f)
        }
    }
    function token0And1(MemPointer config) internal pure returns (IERC20 _token0, IERC20 _token1) {
        //assert(isPairStake(config));
        assembly ("memory-safe") {
            _token0 := and(mload(add(config,0xB3)), MASK_160)
            _token1 := and(mload(add(config,0xC7)), MASK_160)
        }

    }
    function earned(MemPointer config, uint n) internal pure returns (IERC20 _earned, uint dust) {
        assert(n < earnedLength(config));
        bool pairStake = isPairStake(config);

        assembly ("memory-safe") {
            let offset := add(add(mul(n,0x15),0xB3),config)
            if pairStake {
                offset := add(offset,0x28)
            }
            _earned := and(mload(offset), MASK_160)
            dust := shl(and(mload(add(offset,1)), 0xff) , 1)
        }
    }
    function weth(MemPointer config) internal pure returns (IWETH _weth) {
        unchecked {
            uint offset = 0xB3 + earnedLength(config) * 0x15;
            if (isPairStake(config)) offset += 0x28;
        
            assembly ("memory-safe") {
                _weth := and(mload(add(config,offset)), MASK_160)
            }
        }
    }

    function toConfig(bytes memory data) internal pure returns (MemPointer c) {
        assembly ("memory-safe") {
            c := add(data, 0x20)
        }
    }

    function configAddress(IStrategy strategy) internal pure returns (address configAddr) {
        assembly ("memory-safe") {
            mstore(0, or(0xd694000000000000000000000000000000000000000001000000000000000000, shl(80,strategy)))
            configAddr := and(MASK_160, keccak256(0, 23)) //create address, nonce 1
        }
    }

    function configInfo(IStrategy strategy) internal view returns (IStrategy.ConfigInfo memory info) {

        StrategyConfig.MemPointer config;
        address _configAddress = configAddress(strategy);

        assembly ("memory-safe") {
            config := mload(0x40)
            let size := extcodesize(_configAddress)
            if iszero(size) {
                mstore(0, "Strategy config does not exist")
                revert(0,0x20)
            }
            size := sub(size,1)
            extcodecopy(_configAddress, config, 1, size)
            mstore(0x40,add(config, size))
        }

        IERC20 want = config.wantToken();
        uint dust = config.wantDust();
        address _masterchef = config.tactics().masterchef();
        uint24 pid = config.tactics().pid();

        uint len = config.earnedLength();

        IERC20[] memory _earned = new IERC20[](len);
        uint[] memory earnedDust = new uint[](len);
        for (uint i; i < len; i++) {
            (_earned[i], earnedDust[i]) = config.earned(i);
        }

        return IStrategy.ConfigInfo({
            vid: config.vid(),
            want: want,
            wantDust: dust,
            masterchef: _masterchef,
            pid: pid,
            _router: config.router(),
            _magnetite: config.magnetite(),
            earned: _earned,
            earnedDust: earnedDust,
            slippageFactor: config.slippageFactor(),
            feeOnTransfer: config.feeOnTransfer()
        });
    }

}