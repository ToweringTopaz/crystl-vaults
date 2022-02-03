// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./TacticMasterHealer.sol";

interface IMasterchefWithReferral {
    function deposit(uint256 _pid, uint256 _amount, address referrer) external;
}

//Polygon: 0xAfdA790471f2c26cEf82568E22a0feACfA031cD3
contract TacticMasterHealerWithReferral is TacticMasterHealer {
    
    function _vaultDeposit(address masterchefAddress, uint pid, uint256 _amount) external override {
        IMasterchefWithReferral(masterchefAddress).deposit(pid, _amount, address(0));
    }
}