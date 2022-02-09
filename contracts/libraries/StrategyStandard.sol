// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./Tactics.sol";
import "../interfaces/IUniRouter.sol";
import "../interfaces/IMagnetite.sol";

library StrategyStandard {
    
    type MemPointer is uint256;

    uint constant MASK_160 = 0x00ffffffffffffffffffffffffffffffffffffffff;

    function tacticsA(MemPointer config) internal pure returns (Tactics.TacticsA _tacticsA) {
        assembly {
            _tacticsA := mload(config)
        }
    }

    function tactics(MemPointer config) internal pure returns (Tactics.TacticsA _tacticsA, Tactics.TacticsB _tacticsB) {
        assembly {
            _tacticsA := mload(config)
            _tacticsB := mload(add(config,0x20))
        }
    }
    function wantToken(MemPointer config) internal pure returns (IERC20 want, uint256 dust) {
        assembly {
            want := and(mload(add(config,0x34)), MASK_160)
            dust := shl(and(mload(add(config,0x35)), 0xff),1)
        }
    }
    function router(MemPointer config) internal pure returns (IUniRouter _router) {
        assembly {
            _router := and(mload(add(config,0x49)), MASK_160)
        }
    }
    function magnetite(MemPointer config) internal pure returns (IMagnetite _magnetite) {
        assembly {
            _magnetite := and(mload(add(config,0x5D)), MASK_160)
        }        
    }
    function slippageFactor(MemPointer config) internal pure returns (uint _factor) {
        assembly {
            _factor := and(mload(add(config,0x5E)), 0xff)
        }
    }
    function feeOnTransfer(MemPointer config) internal pure returns (bool _isFeeOnTransfer) {
        assembly {
            _isFeeOnTransfer := gt(and(mload(add(config,0x5F)), 0x80), 0)
        }
    }
    function isMaximizer(MemPointer config) internal pure returns (bool _isMaximizer) {
        assembly {
            _isMaximizer := gt(and(mload(add(config,0x5F)), 0x40), 0)
        }
    }
    function isPairStake(MemPointer config) internal pure returns (bool _isPairStake) {
        assembly {
            _isPairStake := gt(and(mload(add(config,0x5F)), 0x20), 0)
        }
    }
    function earnedLength(MemPointer config) internal pure returns (uint _earnedLength) {
        assembly {
            _earnedLength := and(mload(add(config,0x5F)), 0x1f)
        }
    }
    function token0And1(MemPointer config) internal pure returns (IERC20 _token0, IERC20 _token1) {
        assert(isPairStake(config));
        assembly {
            _token0 := and(mload(add(config,0x73)), MASK_160)
            _token1 := and(mload(add(config,0x87)), MASK_160)
        }

    }
    function earned(MemPointer config, uint n) internal pure returns (IERC20 _earned, uint dust) {
        assert(n < earnedLength(config));
        bool pairStake = isPairStake(config);

        assembly {
            let offset := add(add(mul(n,0x15),0x73),config)
            if pairStake {
                offset := add(offset,0x28)
            }
            _earned := and(mload(offset), MASK_160)
            dust := shl(and(mload(add(offset,1)), 0xff) , 1)
        }
    }
    function targetVid(MemPointer config) internal pure returns (uint256 _targetVid) {
        assert(isMaximizer(config));
        uint offset = 0x73 + earnedLength(config) * 0x14;
        if (isPairStake(config)) offset += 0x28;

        assembly {
            _targetVid := mload(add(config,offset))
        }
    }
    function targetWant(MemPointer config) internal pure returns (IERC20 _targetWant) {
        assert(isMaximizer(config));
        uint offset = 0x93 + earnedLength(config) * 0x14;
        if (isPairStake(config)) offset += 0x28;

        assembly {
            _targetWant := and(mload(add(config,offset)), MASK_160)
        }
    }


    function generateConfig(
        Tactics.TacticsA _tacticsA,
        Tactics.TacticsB _tacticsB,
        address _wantToken,
        uint8 _wantDust,
        address _router,
        address _magnetite,
        address _targetVault,
        address _targetWant,
        uint8 _slippageFactor,
        bool _feeOnTransfer,
        address[] memory _earned,
        uint8[] memory _earnedDust
    ) public view returns (bytes memory configData) {
        require(_earned.length > 0 && _earned.length < 0x20, "earned.length invalid");
        require(_earned.length == _earnedDust.length, "earned/dust length mismatch");
        uint8 vaultType = uint8(_earned.length);
        if (_feeOnTransfer) vaultType += 0x80;
        
        address swapToToken = _wantToken;
        if (_targetVault != address(0)) {
            vaultType += 0x40;       
            swapToToken = _targetWant; 
        }
        configData = abi.encodePacked(_tacticsA, _tacticsB, _wantToken, _wantDust, _router, _magnetite, _slippageFactor);
        
        //Look for LP tokens. If not, want must be a single-stake
        try IUniPair(swapToToken).token0() returns (IERC20 _token0) {
            vaultType += 0x20;
            IERC20 _token1 = IUniPair(address(swapToToken)).token1();
            configData = abi.encodePacked(configData, vaultType, _token0, _token1);
        } catch { //if not LP, then single stake
            configData = abi.encodePacked(configData, vaultType);
        }

        for (uint i; i < _earned.length; i++) {
            configData = abi.encodePacked(configData, _earned[i], _earnedDust[i]);
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
}