// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

import "./BaseStrategySwapLogic.sol";
import "./BaseStrategyVHERC20.sol";
import "./BaseStrategyTactician.sol";

//This is a strategy contract which can be expected to support 99% of pools. Tactic contracts provide the pool interface.
contract StrategyVHStandard is BaseStrategyVHERC20, BaseStrategyTactician {

    constructor(
        LibBaseStrategy.SettingsInput memory _settings,
        address[] memory _earned
    ) BaseStrategy(_settings)
        BaseStrategyVaultHealer(_settings.vaultHealerAddress)
        BaseStrategyTactician(_settings)
        BaseStrategySwapLogic(_settings.wantAddress, address(0), _earned)
    {}
        
}