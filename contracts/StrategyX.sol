// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "./Strategy.sol";
import "./interfaces/IDragonLair.sol";


contract StrategyXRewards is Strategy {
    using StrategyConfig for StrategyConfig.MemPointer;

    function _deployMaximizerImplementation() internal virtual returns (IStrategy) {
        return new MaximizerStrategyXRewards();
    }
}