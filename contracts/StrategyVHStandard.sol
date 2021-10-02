// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./BaseStrategySwapLogic.sol";
import "./BaseStrategyVaultHealer.sol";
import "./BaseStrategyTactician.sol";

//This is a strategy contract which can be expected to support 99% of pools. Tactic contracts provide the pool interface.
contract StrategyVHStandard is BaseStrategySwapLogic, BaseStrategyVaultHealer, BaseStrategyTactician {
    using SafeERC20 for IERC20;
    
    constructor(
        address _masterchefAddress,
        address _tactic,
        uint256 _pid,
        address _vaultChefAddress,
        address _wantAddress,
        Settings memory _settings,
        address[] memory _earned,
        address[][] memory _paths
    ) BaseStrategy(_settings)
        BaseStrategyVaultHealer(_vaultChefAddress)
        BaseStrategyTactician(_masterchefAddress, _tactic, _pid)
        BaseStrategySwapLogic(_wantAddress, _earned, _paths)
    {}
        
}