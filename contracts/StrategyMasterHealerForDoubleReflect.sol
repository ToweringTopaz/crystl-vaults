// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./libs/IMasterchef.sol";
import "./StrategyMasterHealer.sol";

contract StrategyMasterHealerForDoubleReflect is StrategyMasterHealer {

    constructor(
        address[5] memory _configAddress, //vaulthealer, masterchef, unirouter, want, earned
        uint256 _pid,
        uint256 _tolerance,
        address[] memory _earnedToWmaticPath,
        address[] memory _earnedToUsdcPath,
        address[] memory _earnedToCrystlPath,
        address[] memory _earnedToToken0Path,
        address[] memory _earnedToToken1Path
    ) StrategyMasterHealer(
        _configAddress,
        _pid,
        _tolerance, 
        _earnedToWmaticPath,
        _earnedToUsdcPath, 
        _earnedToCrystlPath,
        _earnedToToken0Path,
        _earnedToToken1Path
    ) {
        feeOnTransferSwapMode = true;
        slippageFactor = 800;
    }
}