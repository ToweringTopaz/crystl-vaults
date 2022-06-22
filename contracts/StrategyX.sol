// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "./Strategy.sol";
import "./interfaces/IDragonLair.sol";
import "./MaximizerStrategyX.sol";

contract StrategyX is Strategy {

    function _deployMaximizerImplementation() internal override returns (IStrategy) {
        return new MaximizerStrategyX();
    }
}