// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./Tactics.sol";
import {IERC20Upgradeable as IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./IUniRouter.sol";
import "./IMagnetite.sol";

library VaultConfig {

    type Config is uint256;

    uint constant MASK_160 = 0x00ffffffffffffffffffffffffffffffffffffffff;

    function tactics(Config config) internal pure returns (Tactics.TacticsA tacticsA, Tactics.TacticsB tacticsB) {
        assembly {
            tacticsA := mload(config)
            tacticsB := mload(add(config,0x20))
        }

    }
    function wantToken(Config config) internal pure returns (IERC20 want) {
        assembly {
            want := and(mload(add(config,0x34)), MASK_160)
        }
    }

    function router(Config config) internal pure returns (IUniRouter _router) {
        assembly {
            _router := and(mload(add(config,0x48)), MASK_160)
        }
    }
    function magnetite(Config config) internal pure returns (IMagnetite _magnetite) {
        assembly {
            _magnetite := and(mload(add(config,0x5C)), MASK_160)
        }        
    }
    function slippageFactor(Config config) internal pure returns (uint _factor) {
        assembly {
            _factor := and(mload(add(config,0x5D)), 0xff)
        }
    }
    function dust(Config config) internal pure returns (uint _dust) {
        assembly {
            _dust := shl(and(mload(add(config,0x5E)), 0xff),1)
        }
    }
    function feeOnTransfer(Config config) internal pure returns (bool _isFeeOnTransfer) {
        assembly {
            _isFeeOnTransfer := gt(and(mload(add(config,0x5F)), 0x80), 0)
        }
    }
    function isMaximizer(Config config) internal pure returns (bool _isMaximizer) {
        assembly {
            _isMaximizer := gt(and(mload(add(config,0x5F)), 0x40), 0)
        }
    }
    function isPairStake(Config config) internal pure returns (bool _isPairStake) {
        assembly {
            _isPairStake := gt(and(mload(add(config,0x5F)), 0x20), 0)
        }
    }
    function earnedLength(Config config) internal pure returns (uint _earnedLength) {
        assembly {
            _earnedLength := and(mload(add(config,0x5F)), 0x1f)
        }
    }
    function token0And1(Config config) internal pure returns (IERC20 _token0, IERC20 _token1) {
        assert(isPairStake(config));
        assembly {
            _token0 := and(mload(add(config,0x73)), MASK_160)
            _token1 := and(mload(add(config,0x87)), MASK_160)
        }

    }
    function earned(Config config, uint n) internal pure returns (IERC20 _earned) {
        assert(n < earnedLength(config));
        uint offset = 0x73 + n * 0x14;
        if (isPairStake(config)) offset += 0x28;

        assembly {
            _earned := and(mload(add(config,offset)), MASK_160)
        }
    }
    function targetVault(Config config) internal pure returns (address _targetVault) {
        assert(isMaximizer(config));
        uint offset = 0x73 + earnedLength(config) * 0x14;
        if (isPairStake(config)) offset += 0x28;

        assembly {
            _targetVault := mload(add(config,offset))
        }
    }
    function targetWant(Config config) internal pure returns (IERC20 _targetWant) {
        assert(isMaximizer(config));
        uint offset = 0x87 + earnedLength(config) * 0x14;
        if (isPairStake(config)) offset += 0x28;

        assembly {
            _targetWant := and(mload(add(config,offset)), MASK_160)
        }
    }
    function length(Config config) internal pure returns (uint _length) {
        _length = 0x9F + earnedLength(config) * 0x14;
        if (isPairStake(config)) _length += 0x28;
        if (isMaximizer(config)) _length += 0x34;
    }

    function generateConfig(
        Tactics.TacticsA tacticsA,
        Tactics.TacticsB tacticsB,
        address _wantToken,
        address _router,
        address _magnetite,
        uint8 _slippageFactor,
        uint8 dustPow,
        bool _feeOnTransfer,
        address[] memory _earned,
        address _targetVault
    ) public pure returns (bytes memory configData) {
        require(_earned.length > 0 && _earned.length < 0x20, "earned.length invalid");
        uint8 vaultType = uint8(_earned.length);
        if (_feeOnTransfer) vaultType += 0x80;
        if (_targetVault != address(0)) vaultType += 0x40;
        bool pairStake = uint160(address(_magnetite)) % 2 > 0; //todo: correct logic for pairstake
        if (pairStake) vaultType += 0x20; 

        configData = abi.encodePacked(tacticsA, tacticsB, _wantToken, _router, _magnetite, _slippageFactor, dustPow, vaultType);

        if (pairStake) {
            configData = abi.encodePacked(configData, address(0x4545454545454545454545454545454545454545), address(0x2323232323232323232323232323232323232323));
        }
        configData = abi.encodePacked(configData, _earned);

        if (_targetVault > 0) {
            configData = abi.encodePacked(configData, _targetVault, address(0x0101010101010101010101010101010101010101));
        }

    }

    function configTest() public returns (Tactics.TacticsA tacticsA, Tactics.TacticsB tacticsB, address _wantToken, address _router, address _magnetite, bool _pair, bool _max, uint _len) {
        address[] memory _earned = new address[](1);
        _earned[0] = 0x1313131313131313131313131313131313131313;

        bytes memory configData = generateConfig(
            Tactics.TacticsA.wrap(0xefefefefefefefefefefefefefefefefefefefefefefefefefefefefefefefef),
            Tactics.TacticsB.wrap(0xcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd),
            0xABaBaBaBABabABabAbAbABAbABabababaBaBABaB,
            0x8989898989898989898989898989898989898989,0x6767676767676767676767676767676767676767,255,24,false,_earned,1);

        Config config;
        assembly {
            config := add(configData,0x20)
        }
        (tacticsA, tacticsB) = tactics(config);
        _wantToken = address(wantToken(config));
        _router = address(router(config));
        _magnetite = address(magnetite(config));
        _pair = isPairStake(config);
        _max = isMaximizer(config);
        _len = length(config);
    }

}