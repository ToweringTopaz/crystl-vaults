// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./Tactics.sol";
import "../interfaces/IUniRouter.sol";
import "../interfaces/IMagnetite.sol";
import "../interfaces/IVaultHealer.sol";

library StrategyConfig {
    
    type MemPointer is uint256;

    uint constant MASK_160 = 0x00ffffffffffffffffffffffffffffffffffffffff;

    function vid(MemPointer config) internal pure returns (uint256 _vid) {
        assembly {
            _vid := mload(config)
        }
    }
    function targetVid(MemPointer config) internal pure returns (uint256 _targetVid) {
        assembly {
            _targetVid := shr(0x10, mload(config))
        }
    }
    function isMaximizer(MemPointer config) internal pure returns (bool _isMaximizer) {
        assembly {
            _isMaximizer := gt(shr(0x10, mload(config)), 0)
        }
    }

    function tacticsA(MemPointer config) internal pure returns (Tactics.TacticsA _tacticsA) {
        assembly {
            _tacticsA := mload(add(0x20,config))
        }
    }

    function tactics(MemPointer config) internal pure returns (Tactics.TacticsA _tacticsA, Tactics.TacticsB _tacticsB) {
        assembly {
            _tacticsA := mload(add(0x20,config))
            _tacticsB := mload(add(config,0x40))
        }
    }
    function wantToken(MemPointer config) internal pure returns (IERC20 want, uint256 dust) {
        assembly {
            want := and(mload(add(config,0x54)), MASK_160)
            dust := shl(and(mload(add(config,0x55)), 0xff),1)
        }
    }
    function router(MemPointer config) internal pure returns (IUniRouter _router) {
        assembly {
            _router := and(mload(add(config,0x69)), MASK_160)
        }
    }
    function magnetite(MemPointer config) internal pure returns (IMagnetite _magnetite) {
        assembly {
            _magnetite := and(mload(add(config,0x7D)), MASK_160)
        }        
    }
    function slippageFactor(MemPointer config) internal pure returns (uint _factor) {
        assembly {
            _factor := and(mload(add(config,0x7E)), 0xff)
        }
    }
    function feeOnTransfer(MemPointer config) internal pure returns (bool _isFeeOnTransfer) {
        assembly {
            _isFeeOnTransfer := gt(and(mload(add(config,0x7F)), 0x80), 0)
        }
    }

    function isPairStake(MemPointer config) internal pure returns (bool _isPairStake) {
        assembly {
            _isPairStake := gt(and(mload(add(config,0x7F)), 0x20), 0)
        }
    }
    function earnedLength(MemPointer config) internal pure returns (uint _earnedLength) {
        assembly {
            _earnedLength := and(mload(add(config,0x7F)), 0x1f)
        }
    }
    function token0And1(MemPointer config) internal pure returns (IERC20 _token0, IERC20 _token1) {
        assert(isPairStake(config));
        assembly {
            _token0 := and(mload(add(config,0x93)), MASK_160)
            _token1 := and(mload(add(config,0xA7)), MASK_160)
        }

    }
    function earned(MemPointer config, uint n) internal pure returns (IERC20 _earned, uint dust) {
        assert(n < earnedLength(config));
        bool pairStake = isPairStake(config);

        assembly {
            let offset := add(add(mul(n,0x15),0x93),config)
            if pairStake {
                offset := add(offset,0x28)
            }
            _earned := and(mload(offset), MASK_160)
            dust := shl(and(mload(add(offset,1)), 0xff) , 1)
        }
    }
    function targetWant(MemPointer config) internal pure returns (IERC20 _targetWant) {
        if (isMaximizer(config)) {
            unchecked {
                uint offset = 0x93 + earnedLength(config) * 0x15;
                if (isPairStake(config)) offset += 0x28;
            
                assembly {
                    _targetWant := and(mload(add(config,offset)), MASK_160)
                }
            }
        } else {
            (_targetWant,) = wantToken(config);
        }
    }

    function toConfig(bytes memory data) internal pure returns (MemPointer c) {
        assembly {
            c := add(data, 0x20)
        }
    }

    function test(bytes memory configData) external pure returns (Tactics.TacticsA _tacticsA, Tactics.TacticsB _tacticsB, IERC20 want, uint wantDust, IUniRouter _router, IMagnetite _magnetite) {
        MemPointer c = toConfig(configData);
        (_tacticsA, _tacticsB) = tactics(c);
        (want, wantDust) = wantToken(c);
        _router = router(c);
        _magnetite = magnetite(c);
    }
    function test2(bytes memory configData) external pure returns (uint _slippageFactor, bool _feeOnTransfer, IERC20[] memory _earned, uint[] memory _dust) {
        MemPointer c = toConfig(configData);
        _slippageFactor = slippageFactor(c);
        _feeOnTransfer = feeOnTransfer(c);
        uint len = earnedLength(c);
        _earned = new IERC20[](len);
        _dust = new uint[](len);
        for (uint i; i < len; i++) {
            (_earned[i], _dust[i]) = earned(c, i);
        }
    }

    function generateConfig(
        address vaultHealer,
        Tactics.TacticsA _tacticsA,
        Tactics.TacticsB _tacticsB,
        address _wantToken,
        uint8 _wantDust,
        address _router,
        address _magnetite,
        uint8 _slippageFactor,
        bool _feeOnTransfer,
        address[] memory _earned,
        uint8[] memory _earnedDust,
        uint _targetVid
    ) external view returns (bytes memory configData) {
        console.log("made it into generateConfig");
        require(_earned.length > 0 && _earned.length < 0x20, "earned.length invalid");
                console.log("1");

        require(_earned.length == _earnedDust.length, "earned/dust length mismatch");
                console.log("1");

        uint8 vaultType = uint8(_earned.length);
                        console.log("1");

        if (_feeOnTransfer) vaultType += 0x80;
                        console.log("1");

        configData = abi.encodePacked(_tacticsA, _tacticsB, _wantToken, _wantDust, _router, _magnetite, _slippageFactor);
                        console.log("1");

		
		IERC20 _targetWant = IERC20(_wantToken);
        if (_targetVid > 0) {
            (_targetWant,,,,,) = IVaultHealer(vaultHealer).vaultInfo(_targetVid);
        }

        //Look for LP tokens. If not, want must be a single-stake
        try IUniPair(address(_targetWant)).token0() returns (IERC20 _token0) {
            vaultType += 0x20;
            IERC20 _token1 = IUniPair(address(_targetWant)).token1();
            configData = abi.encodePacked(configData, vaultType, _token0, _token1);
        } catch { //if not LP, then single stake
            configData = abi.encodePacked(configData, vaultType);
        }

        for (uint i; i < _earned.length; i++) {
            configData = abi.encodePacked(configData, _earned[i], _earnedDust[i]);
        }

		if (_targetVid > 0) 
			configData = abi.encodePacked(configData, _targetWant);
    }
}