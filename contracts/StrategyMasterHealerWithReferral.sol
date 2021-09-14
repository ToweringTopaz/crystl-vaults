// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./StrategyMasterHealer.sol";

contract StrategyMasterHealerWithReferral is StrategyMasterHealer {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    function _vaultDeposit(uint256 _amount) internal override {
        IMasterchef(masterchefAddress).deposit(pid, _amount, referrer); //what should I set referrer to?
    }
    
}