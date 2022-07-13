// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "./StrategyWrapperToken.sol";
import "./interfaces/IAToken.sol";

contract StrategyAToken is StrategyWrapperToken {
    using StrategyConfig for StrategyConfig.MemPointer;
    using Tactics for Tactics.TacticsA;
	using Tactics for Tactics.TacticsB;

    function _vaultSharesTotal() internal view override returns (uint256) {
        (,uint balance,, uint ratio) = IAToken(address(wrapperToken())).getAccountSnapshot(address(this));
        return balance*ratio;
    }

    function _vaultEmergencyWithdraw() internal override {

        Tactics.TacticsB tacticsB = config.tacticsB();
        if (Tactics.TacticsB.unwrap(tacticsB) << 196 == 0) {

            IAToken aToken = IAToken(address(wrapperToken()));
            uint balance = aToken.balanceOf(address(this));
            if (balance > 0) aToken.redeem(balance);
        }
    }

    function _sync() internal override {
        IAToken(address(config.tacticsA().masterchef())).accrueInterest();        
    }
}