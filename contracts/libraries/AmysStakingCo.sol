// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IMasterHealer.sol";

enum ChefType { UNKNOWN, MASTERCHEF, MINICHEF }

library AmysStakingCo {

    error UnknownChefType(address chef);
    error PoolLengthZero(address chef);

    uint8 constant CHEF_UNKNOWN = 0;
    uint8 constant CHEF_MASTER = 1;
    uint8 constant CHEF_MINI = 2;

    function getMCPoolData(address chef) external view returns (uint8 chefType, address[] memory lpTokens, uint256[] memory allocPoint) {

        uint len = IMasterHealer(chef).poolLength();
        if (len == 0) revert PoolLengthZero(chef);

        chefType = identifyChefType(chef);
        if (chefType == 0) revert UnknownChefType(chef);

        lpTokens = new address[](len);
        allocPoint = new uint256[](len);

        if (chefType == CHEF_MASTER) {
            for (uint i; i < len; i++) {
                (bool success, bytes memory data) = chef.staticcall(abi.encodeWithSignature("poolInfo(uint256)", i));
                if (success) (lpTokens[i], allocPoint[i]) = abi.decode(data,(address, uint256));
            }
        } else if (chefType == CHEF_MINI) {
            for (uint i; i < len; i++) {
                (bool success, bytes memory data) = chef.staticcall(abi.encodeWithSignature("lpToken(uint256)", i));
                if (!success) continue;
                lpTokens[i] = abi.decode(data,(address));

                (success, data) = chef.staticcall(abi.encodeWithSignature("poolInfo(uint256)", i));
                if (success) (,, allocPoint[i]) = abi.decode(data,(uint128,uint64,uint64));
            }
        }

    }

    //assumes at least one pool exists i.e. chef.poolLength() > 0
    function identifyChefType(address chef) public view returns (uint8 chefType) {

        (bool success,) = chef.staticcall(abi.encodeWithSignature("lpToken(uint256)", 0));

        if (success && checkMiniChef(chef)) {
            return CHEF_MINI;
        }
        if (!success && checkMasterChef(chef)) {
            return CHEF_MASTER;
        }
        
        return CHEF_UNKNOWN;
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
        if (!success) return false;

        (,uint lastRewardTime,) = abi.decode(data,(uint256,uint256,uint256));
        valid = lastRewardTime <= block.timestamp && lastRewardTime > 2**30;
    }

}