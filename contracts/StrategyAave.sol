// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./Strategy.sol";
import "./interfaces/IAaveIncentivesController.sol";
import "./interfaces/IProtocolDataProvider.sol";
import "hardhat/console.sol";

contract StrategyAave is Strategy {
    using StrategyConfig for StrategyConfig.MemPointer;
    IAaveIncentivesController public constant Controller = IAaveIncentivesController(0x357D51124f59836DeD84c8a1730D72B749d8BC23);
    IProtocolDataProvider public constant DataProvider = IProtocolDataProvider(0x7551b5D2763519d4e37e8B81929D336De671d46d);
    address public constant AaveLendingPool = 0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf;

    constructor(address _vaultHealer) Strategy(_vaultHealer) {}

    function _vaultHarvest(IERC20 _wantToken) internal override {
        console.log("made it into StrategyAave _vaultHarvest");
        uint _tacticsA = Tactics.TacticsA.unwrap(config.tacticsA());
        address masterchef = address(uint160(_tacticsA >> 96));
        if (masterchef == address(AaveLendingPool)) {
            address[] memory address_array = new address[](1);
            address_array[0] = address(_wantToken);
            console.log(address_array[0]);
            Controller.claimRewards(address_array, type(uint256).max, address(this));
            console.log("done claiming rewards");
        } else super._vaultHarvest(_wantToken);
    }

    function _vaultSharesTotal(IERC20 _wantToken) internal view override returns (uint256) {
        uint _tacticsA = Tactics.TacticsA.unwrap(config.tacticsA());
        address masterchef = address(uint160(_tacticsA >> 96));
        if (masterchef == address(AaveLendingPool)) {
            (uint256 aTokenBalance,,,,,,,,) = DataProvider.getUserReserveData(address(_wantToken), address(this));
            console.log("aTokenBalance: ", aTokenBalance);
            return aTokenBalance;
        } else return super._vaultSharesTotal(_wantToken);
    }
}