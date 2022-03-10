// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./Strategy.sol";
import "./interfaces/IAaveIncentivesController.sol";

contract StrategyAave is Strategy {
    using StrategyConfig for StrategyConfig.MemPointer;
    IAaveIncentivesController public constant Controller = IAaveIncentivesController(0x357D51124f59836DeD84c8a1730D72B749d8BC23);

    constructor(address _vaultHealer) Strategy(_vaultHealer) {}

    function _vaultHarvest(IERC20 _wantToken) internal override {
        address[] memory address_array = new address[](1);
        address_array[0] = address(_wantToken);
        Controller.claimRewards(address_array, type(uint256).max, address(this));
    }
}