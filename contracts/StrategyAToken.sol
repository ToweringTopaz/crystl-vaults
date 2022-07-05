// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "./Strategy.sol";
import "./interfaces/IAToken.sol";

contract StrategyAToken is Strategy {
    using StrategyConfig for StrategyConfig.MemPointer;
    using Tactics for Tactics.TacticsA;

    function _earn(Fee.Data[3] calldata fees, address operator, bytes calldata data) internal override returns (bool success, uint256 __wantLockedTotal) {
        if (isBasicATokenStrategy()) {
            _sync();
            uint wantBalance = config.wantToken().balanceOf(address(this));
            success = wantBalance > config.wantDust();
            __wantLockedTotal = wantBalance + (success ? _farm() : _wantLockedTotal());
        } else {
            return super._earn(fees, operator, data);
        }
    }

    function isBasicATokenStrategy() internal pure returns (bool) {
        (,Tactics.TacticsB tacticsB) = config.tactics();
        return Tactics.TacticsB.unwrap(tacticsB) << 128 == 0   //zero harvest/emergency vault withdraw tactic
            && config.earnedLength() == 1   //only one earned token
            && config.earnedToken(0) == config.wantToken(); //only earning the want token
    }

    function _vaultSharesTotal() internal view override returns (uint256) {
        (,uint balance,, uint ratio) = IAToken(address(config.tacticsA().masterchef())).getAccountSnapshot(address(this));
        return balance*ratio;
    }

    function _vaultEmergencyWithdraw() internal override {

        (Tactics.TacticsA tacticsA, Tactics.TacticsB tacticsB) = config.tactics();
        if (Tactics.TacticsB.unwrap(tacticsB) << 196 == 0) {

            IAToken aToken = IAToken(address(tacticsA.masterchef()));
            uint balance = aToken.balanceOf(address(this));
            if (balance > 0) aToken.redeem(balance);
        }
    }

    function _sync() internal override {
        IAToken(address(config.tacticsA().masterchef())).accrueInterest();        
    }

    function _initialSetup() internal override {
        require(!(config.isMaximizer() && isBasicATokenStrategy()), "StrategyAToken cannot be a maximizer because it does not harvest its earnings");
        super._initialSetup();
    }

}