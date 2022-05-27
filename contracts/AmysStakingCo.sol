// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "./libraries/AmysStakingLib.sol";

contract AmysStakingCo {
    using Address for address;
    using StrategyConfig for StrategyConfig.MemPointer;
    using AmysStakingLib for AmysStakingLib.WantPid;

    error UnknownChefType(address chef);
    error PoolLengthZero(address chef);
    error BadChefType(address chef, uint8 chefType);

    uint8 constant CHEF_UNKNOWN = 0;
    uint8 constant CHEF_MASTER = 1;
    uint8 constant CHEF_MINI = 2;
    uint8 constant CHEF_STAKING_REWARDS = 3;
    uint8 constant OPERATOR = 255;

    struct ChefContract {
        uint8 chefType;
        uint64 pidLast;
        mapping(address => AmysStakingLib.WantPid) wantPid;
    }

    mapping(address => ChefContract) public chefs;

    function findPool(address chef, address wantToken) external view returns (AmysStakingLib.WantPid memory) {
        return chefs[chef].wantPid[wantToken];
    }

    function sync(address _chef) external returns (uint64 endIndex) {
        uint64 len = getLength(_chef, _identifyChefType(_chef));
        ChefContract storage chef = chefs[_chef];
        string memory wantSig;
        if (chef.chefType == CHEF_MASTER)
            wantSig = "poolInfo(uint256)";
        else if (chef.chefType == CHEF_MINI)
            wantSig = "lpToken(uint256)";
        else
             revert BadChefType(_chef, chef.chefType);
        
        uint64 i = chef.pidLast;
        for (; i < len && gasleft() > 2**16; i++) {

            (bool success, bytes memory data) = _chef.staticcall(abi.encodeWithSignature(wantSig, i));
            if (success) {
                address wantAddr = abi.decode(data,(address));
                chef.wantPid[wantAddr].push(i);
            }
        }
        return chef.pidLast = i;
    }


    function getMCPoolData(address chef) public view returns (uint startIndex, uint endIndex, uint8 chefType, address[] memory lpTokens, uint256[] memory allocPoint, uint256[] memory endTime) {

        chefType = identifyChefType(chef);
        uint len = getLength(chef, chefType);
        if (len == 0) revert PoolLengthZero(chef);
        if (len > endIndex) len = endIndex;

        lpTokens = new address[](len);
        allocPoint = new uint256[](len);

        if (chefType == CHEF_MASTER) {
            for (uint i = startIndex; i < len; i++) {
                (bool success, bytes memory data) = chef.staticcall(abi.encodeWithSignature("poolInfo(uint256)", i));
                if (success) (lpTokens[i - startIndex], allocPoint[i - startIndex]) = abi.decode(data,(address, uint256));
            }
        } else if (chefType == CHEF_MINI) {
            for (uint i = startIndex; i < len; i++) {
                (bool success, bytes memory data) = chef.staticcall(abi.encodeWithSignature("lpToken(uint256)", i));
                if (!success) continue;
                lpTokens[i] = abi.decode(data,(address));

                (success, data) = chef.staticcall(abi.encodeWithSignature("poolInfo(uint256)", i));
                if (success) (,, allocPoint[i - startIndex]) = abi.decode(data,(uint128,uint64,uint64));
            }
        } else if (chefType == CHEF_STAKING_REWARDS) {
            endTime = new uint256[](len);
            for (uint i = startIndex; i < len; i++) {
                address spawn = addressFrom(chef, i + 1);
                if (spawn.code.length == 0) continue;

                (bool success, bytes memory data) = spawn.staticcall(abi.encodeWithSignature("stakingToken()"));
                if (!success) continue;
                lpTokens[i - startIndex] = abi.decode(data,(address));

                (success, data) = spawn.staticcall(abi.encodeWithSignature("periodFinish()"));
                if (!success) continue;
                uint _endTime = abi.decode(data,(uint256));
                endTime[i - startIndex] = _endTime;
                if (_endTime < block.timestamp) continue;

                (success, data) = spawn.staticcall(abi.encodeWithSignature("rewardRate()"));
                if (success) (,, allocPoint[i - startIndex]) = abi.decode(data,(uint128,uint64,uint64));
            }
        }
    }

    function getLength(address chef, uint8 chefType) public view returns (uint32 len) {
        if (chefType == CHEF_MASTER || chefType == CHEF_MINI) {
                len = uint32(IMasterHealer(chef).poolLength());
            } else if (chefType == CHEF_STAKING_REWARDS) {
                len = uint32(createFactoryNonce(chef) - 1);
            }
    }


    function _identifyChefType(address chef) internal returns (uint8 chefType) {
        return chefs[chef].chefType = identifyChefType(chef);
    }

    //assumes at least one pool exists i.e. chef.poolLength() > 0
    function identifyChefType(address chef) public view returns (uint8 chefType) {
        if (chefs[chef].chefType != 0) return chefs[chef].chefType;
        (bool success,) = chef.staticcall(abi.encodeWithSignature("lpToken(uint256)", 0));

        if (success && checkMiniChef(chef)) {
            return CHEF_MINI;
        }
        if (!success && checkMasterChef(chef)) {
            return CHEF_MASTER;
        }
        if (checkStakingRewardsFactory(chef)) {
            return CHEF_STAKING_REWARDS;
        }
        
        revert UnknownChefType(chef);
    }

    function checkMasterChef(address chef) internal view returns (bool valid) { 
        (bool success, bytes memory data) = chef.staticcall(abi.encodeWithSignature("poolInfo(uint256)", 0));
        if (!success) return false;
        (uint lpTokenAddress,,uint lastRewardBlock) = abi.decode(data,(uint256,uint256,uint256));
        valid = ((lpTokenAddress > type(uint96).max && lpTokenAddress < type(uint160).max) || lpTokenAddress == 0) && 
            lastRewardBlock <= block.number;
    }

    function checkMiniChef(address chef) internal view returns (bool valid) { 
        (bool success, bytes memory data) = chef.staticcall(abi.encodeWithSignature("poolInfo(uint256)", 0));
        if (!success) return false;
        (success,) = chef.staticcall(abi.encodeWithSignature("lpToken(uint256)", 0));
        if (!success || data.length < 0x40) return false;

        (,uint lastRewardTime) = abi.decode(data,(uint256,uint256));
        valid = lastRewardTime <= block.timestamp && lastRewardTime > 2**30;
    }

    function checkStakingRewardsFactory(address chef) internal view returns (bool valid) {
        (bool success, bytes memory data) = chef.staticcall(abi.encodeWithSignature("stakingRewardsGenesis()"));
        valid = success && data.length == 32;
    }

    function addressFrom(address _origin, uint _nonce) internal pure returns (address) {
        bytes32 data;
        if(_nonce == 0x00)          data = keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, bytes1(0x80)));
        else if(_nonce <= 0x7f)     data = keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, uint8(_nonce)));
        else if(_nonce <= 0xff)     data = keccak256(abi.encodePacked(bytes1(0xd7), bytes1(0x94), _origin, bytes1(0x81), uint8(_nonce)));
        else if(_nonce <= 0xffff)   data = keccak256(abi.encodePacked(bytes1(0xd8), bytes1(0x94), _origin, bytes1(0x82), uint16(_nonce)));
        else if(_nonce <= 0xffffff) data = keccak256(abi.encodePacked(bytes1(0xd9), bytes1(0x94), _origin, bytes1(0x83), uint24(_nonce)));
        else                        data = keccak256(abi.encodePacked(bytes1(0xda), bytes1(0x94), _origin, bytes1(0x84), uint32(_nonce))); // more than 2^32 nonces not realistic

        return address(uint160(uint256(data)));
    }

    //The nonce of a factory contract that uses CREATE, assuming no child contracts have selfdestructed
    function createFactoryNonce(address _origin) public view returns (uint) {

        uint n = 1;
        uint top = 2**32;
    
        unchecked {
            for (uint p = 1; p < top && p > 0;) {
                address spawn = addressFrom(_origin, n + p); //
                if (spawn.isContract()) {
                    n += p;
                    p *= 2;
                    if (n + p > top) p = (top - n) / 2;
                } else {
                    top = n + p;
                    p /= 2;
                }
            }
            return n;
        }
    }

    struct LPTokenInfo {
        bool isLPToken;
        address token0;
        address token1;
        address factory;
        bytes32 symbol;
        bytes32 token0symbol;
        bytes32 token1symbol;
    }

    function lpTokenInfo(address token) public view returns (LPTokenInfo memory info) {
        (bool isLP, address token0, address token1, address factory) = checkLP(token);
        info = LPTokenInfo({
            isLPToken: isLP,
            token0: token0,
            token1: token1,
            factory: factory,
            symbol: getSymbol(token),
            token0symbol: getSymbol(token0),
            token1symbol: getSymbol(token1)
        });
    }

    function lpTokenInfo(address vaultHealer, uint vid) public view returns (LPTokenInfo memory info) {
        return lpTokenInfo(address(VaultChonk.strat(IVaultHealer(vaultHealer), vid).wantToken()));
    }

    function getSymbol(address token) internal view returns (bytes32) {
        if (token == address(0)) return bytes32(0);
        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSignature("symbol()"));
        if (!success) return bytes32(0);
        return bytes32(bytes(abi.decode(data,(string))));
    }

    function lpTokenInfo(address[] memory tokens) public view returns (LPTokenInfo[] memory info) {
        info = new LPTokenInfo[](tokens.length);
        for (uint i; i < tokens.length; i++) {
            info[i] = lpTokenInfo(tokens[i]);
        }
    }

    function checkLP(address token) public view returns (bool isLP, address token0, address token1, address factory) {
        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSignature("token0()"));
        if (success && data.length >= 32) {
            token0 = abi.decode(data,(address));

            (success, data) = token.staticcall(abi.encodeWithSignature("token1()"));
            if (token0 != address(0) && success && data.length >= 32) {
                token1 = abi.decode(data,(address));

                (success, data) = token.staticcall(abi.encodeWithSignature("factory()"));
                if (token1 != address(0) && success && data.length >= 32) {
                    factory = abi.decode(data,(address));

                    (success, data) = factory.staticcall(abi.encodeWithSignature("getPair(address,address)", token0, token1));
                    if (factory != address(0) && success && data.length >= 32) {
                        address pairFound = abi.decode(data,(address));
                        isLP = (pairFound == token);
                    }
                }
            }
        }
    }

    function strat(IVaultHealer vaultHealer, uint vid) public pure returns (IStrategy) {
        return VaultChonk.strat(vaultHealer, vid);
    }

    function configInfo(IVaultHealer vaultHealer, uint vid) public view returns (IStrategy.ConfigInfo memory) {
        return configInfo(strat(vaultHealer, vid));
    }

    function configInfo(IStrategy strategy) public view returns (IStrategy.ConfigInfo memory) {
        return StrategyConfig.configInfo(strategy);
    }

}