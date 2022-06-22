// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "./BaseStrategy.sol";

//Standard v3 Maximizer Strategy
contract MaximizerStrategy is BaseStrategy {
    using StrategyConfig for StrategyConfig.MemPointer;
    using Fee for Fee.Data[3];
    using VaultChonk for IVaultHealer;

    function getMaximizerImplementation() external override view returns (IStrategy) {
        return implementation;
    }
    function _isMaximizer() internal override view returns (bool) { 
        assert(config.isMaximizer() || this == implementation);
        return true; 
    }
    function _isBaseVault() internal override view returns (bool) { 
        assert(config.isMaximizer() || this == implementation);
        return false;
    }

    function getTargetWant() internal view returns (IERC20 targetWant, uint dust, uint balance) {
        ConfigInfo memory targetConfig = VaultChonk.strat(IVaultHealer(msg.sender), config.vid() >> 16).configInfo();
        return (targetConfig.want, targetConfig.wantDust, targetWant.balanceOf(address(this)));
    }

    function earn(Fee.Data[3] calldata fees, address, bytes calldata) external virtual getConfig onlyVaultHealer guardPrincipal returns (bool success, uint256 __wantLockedTotal) {
        _sync();
        (IERC20 targetWant, uint targetWantDust, uint targetWantAmt) = getTargetWant();

        _vaultHarvest(); //Perform the harvest of earned reward tokens
        
        for (uint i; i < config.earnedLength(); i++) { //Sell earned tokens
            (IERC20 earnedToken, uint dust) = config.earned(i);
            
            if (earnedToken != targetWant) { //Don't sell targetWant tokens
                uint256 earnedAmt = earnedToken.balanceOf(address(this));
                if (earnedAmt > dust) { //Only swap if enough has been earned
                    safeSwap(earnedAmt, earnedToken, config.weth()); //swap to the native gas token
                }
            }
        }

        uint targetWantBalance = targetWant.balanceOf(address(this));        
        if (targetWantBalance > targetWantDust) {
            targetWantAmt = fees.payTokenFeePortion(targetWant, targetWantBalance - targetWantAmt) + targetWantAmt;
            success = true;
        }
        if (unwrapAllWeth()) {
            fees.payEthPortion(address(this).balance); //pays the fee portion
            success = true;
        }

        if (success) {
            
            try IVaultHealer(msg.sender).maximizerDeposit{value: address(this).balance}(config.vid(), targetWantAmt, "") {} //deposit the rest, and any targetWant tokens
            catch {  //compound want instead if maximizer doesn't work
                wrapAllEth();
                IWETH weth = config.weth();
                uint wethAmt = weth.balanceOf(address(this));
                if (wethAmt > WETH_DUST) {
                    wethAmt = fees.payWethPortion(weth, wethAmt); //pay fee portion
                    swapToWantToken(wethAmt, weth);
                }
                if (targetWantAmt > targetWantDust && targetWant != config.wantToken()) {
                    swapToWantToken(targetWantAmt, targetWant);
                }
                emit Strategy_MaximizerDepositFailure();
            }
        }

        __wantLockedTotal = config.wantToken().balanceOf(address(this)) + _farm();
    }

}