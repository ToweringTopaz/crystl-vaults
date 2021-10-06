// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./BaseStrategySwapLogic.sol";
import "./BaseStrategyVaultHealer.sol";
import "./BaseStrategyTactician.sol";

//This is a strategy contract which can be expected to support 99% of pools. Tactic contracts provide the pool interface.
contract StrategyVHStandard is BaseStrategyVaultHealer, BaseStrategyTactician {

    constructor(
        address _masterchefAddress,
        address _tactic,
        uint256 _pid,
        address _vaultHealerAddress,
        address _wantAddress,
        Settings memory _settings,
        address[] memory _earned
    ) BaseStrategy(_settings)
        BaseStrategyVaultHealer(_vaultHealerAddress)
        BaseStrategyTactician(_masterchefAddress, _tactic, _pid)
        BaseStrategySwapLogic(_wantAddress, address(0), _earned)
    {}
        
}