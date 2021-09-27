// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./libs/IMasterchefWithReferral.sol";
import "./StrategyMasterHealer.sol";

contract StrategyMasterHealerWithReferral is StrategyMasterHealer {

    constructor(
        Addresses memory _addresses,
        Settings memory _settings,
        address[][] memory _paths,  //need paths for earned to each of (wmatic, dai, crystl, token0, token1)
        address _wantAddress,
        address _earnedAddress,
        uint256 _pid
    ) StrategyMasterHealer(_addresses, _settings, _paths, _pid) {}

    function _vaultDeposit(uint256 _amount) internal override {
        IMasterchefWithReferral(addresses.masterchef).deposit(pid, _amount, address(0));
    }
}