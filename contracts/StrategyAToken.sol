// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "./Strategy.sol";
import "./interfaces/IAToken.sol";

contract StrategyAToken is Strategy {
    using StrategyConfig for StrategyConfig.MemPointer;
    using Tactics for Tactics.TacticsA;

    IStrategy immutable _maximizerImplementation;

    //IMPORTANT: The argument here is the STANDARD STRATEGY IMPLEMENTATION
    constructor(address _maxiImpl) Strategy(BaseStrategy(payable(_maxiImpl)).vaultHealer()) {
        _maximizerImplementation = IStrategy(_maxiImpl);
    }

    function getMaximizerImplementation() external view override returns (IStrategy) {
        return _maximizerImplementation;
    }

    function _vaultSharesTotal() internal view override returns (uint256) {
        (,uint balance,, uint ratio) = IAToken(address(config.wantToken())).getAccountSnapshot(address(this));
        return balance*ratio;
    }

    function _vaultEmergencyWithdraw() internal override {

        IAToken want = IAToken(address(config.wantToken()));
        uint balance = want.balanceOf(address(this));
        if (balance > 0) want.redeem(balance);
    }

    function _sync() internal override {
        IAToken(address(config.wantToken())).accrueInterest();        
    }

    function _initialSetup() internal override {
        require(!config.isMaximizer(), "StrategyAToken cannot be a maximizer");
        super._initialSetup();
    }

}