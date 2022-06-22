// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "./Tactics.sol";
import "../interfaces/IUniRouter.sol";
import "../interfaces/IMagnetite.sol";
import "../interfaces/IVaultHealer.sol";

library StrategyConfig {
    using StrategyConfig for MemPointer;
    
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

    function tacticsA(MemPointer config) internal pure returns (Tactics.TacticsA _tacticsA) {
        assembly ("memory-safe") {
            _tacticsA := mload(add(0x20,config))
        }
    }

    function tactics(MemPointer config) internal pure returns (Tactics.TacticsA _tacticsA, Tactics.TacticsB _tacticsB) {
        assembly ("memory-safe") {
            _tacticsA := mload(add(0x20,config))
            _tacticsB := mload(add(config,0x40))
        }
    }
    function masterchef(MemPointer config) internal pure returns (address) {
        return Tactics.masterchef(tacticsA(config));
    }
    function wantToken(MemPointer config) internal pure returns (IERC20 want) {
        assembly ("memory-safe") {
            want := and(mload(add(config,0x54)), MASK_160)
        }
    }
    function wantDust(MemPointer config) internal pure returns (uint256 dust) {
        assembly ("memory-safe") {
            dust := shl(and(mload(add(config,0x55)), 0xff),1)
        }
    }
    function router(MemPointer config) internal pure returns (IUniRouter _router) {
        assembly ("memory-safe") {
            _router := and(mload(add(config,0x69)), MASK_160)
        }
    }
    function magnetite(MemPointer config) internal pure returns (IMagnetite _magnetite) {
        assembly ("memory-safe") {
            _magnetite := and(mload(add(config,0x7D)), MASK_160)
        }        
    }
    function slippageFactor(MemPointer config) internal pure returns (uint _factor) {
        assembly ("memory-safe") {
            _factor := and(mload(add(config,0x7E)), 0xff)
        }
    }
    function feeOnTransfer(MemPointer config) internal pure returns (bool _isFeeOnTransfer) {
        assembly ("memory-safe") {
            _isFeeOnTransfer := gt(and(mload(add(config,0x7F)), 0x80), 0)
        }
    }

    function isPairStake(MemPointer config) internal pure returns (bool _isPairStake) {
        assembly ("memory-safe") {
            _isPairStake := gt(and(mload(add(config,0x7F)), 0x20), 0)
        }
    }
    function earnedLength(MemPointer config) internal pure returns (uint _earnedLength) {
        assembly ("memory-safe") {
            _earnedLength := and(mload(add(config,0x7F)), 0x1f)
        }
    }
    function token0And1(MemPointer config) internal pure returns (IERC20 _token0, IERC20 _token1) {
        //assert(isPairStake(config));
        assembly ("memory-safe") {
            _token0 := and(mload(add(config,0x93)), MASK_160)
            _token1 := and(mload(add(config,0xA7)), MASK_160)
        }

    }
    function earned(MemPointer config, uint n) internal pure returns (IERC20 _earned, uint dust) {
        assert(n < earnedLength(config));
        bool pairStake = isPairStake(config);

        assembly ("memory-safe") {
            let offset := add(add(mul(n,0x15),0x93),config)
            if pairStake {
                offset := add(offset,0x28)
            }
            _earned := and(mload(offset), MASK_160)
            dust := shl(and(mload(add(offset,1)), 0xff) , 1)
        }
    }

    function earnedToken(MemPointer config, uint n) internal pure returns (IERC20 _earned) {
        assert(n < earnedLength(config));
        bool pairStake = isPairStake(config);

        assembly ("memory-safe") {
            let offset := add(add(mul(n,0x15),0x93),config)
            if pairStake {
                offset := add(offset,0x28)
            }
            _earned := and(mload(offset), MASK_160)
        }
    }
    function earnedDust(MemPointer config, uint n) internal pure returns (uint dust) {
        assert(n < earnedLength(config));
        bool pairStake = isPairStake(config);

        assembly ("memory-safe") {
            let offset := add(add(mul(n,0x15),0x94),config)
            if pairStake {
                offset := add(offset,0x28)
            }
            dust := shl(and(mload(offset), 0xff) , 1)
        }
    }

    function weth(MemPointer config) internal pure returns (IWETH _weth) {
        unchecked {
            uint offset = 0x93 + earnedLength(config) * 0x15;
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
        bytes32 _tacticsA = Tactics.TacticsA.unwrap(config.tacticsA());
        address _masterchef = address(bytes20(_tacticsA));
        uint24 pid = uint24(uint(_tacticsA) >> 72);

        uint len = config.earnedLength();

        IERC20[] memory _earned = new IERC20[](len);
        uint[] memory _earnedDust = new uint[](len);
        for (uint i; i < len; i++) {
            (_earned[i], _earnedDust[i]) = config.earned(i);
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
            earnedDust: _earnedDust,
            slippageFactor: config.slippageFactor(),
            feeOnTransfer: config.feeOnTransfer()
        });
    }

}