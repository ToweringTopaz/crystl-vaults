// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "./MaximizerStrategy.sol";

contract MaximizerStrategyX is MaximizerStrategy {
    using StrategyConfig for StrategyConfig.MemPointer;
    using Fee for Fee.Data[3];

    function _earn(Fee.Data[3] calldata fees, address, bytes calldata) internal override returns (bool success, uint256 __wantLockedTotal) {
        _sync();
        
        //Get balances 
        (IERC20 targetWant, uint targetWantDust, uint targetWantAmt) = getTargetWant();
        IERC20 _wantToken = config.wantToken();
        uint wantAmt = _wantToken.balanceOf(address(this)); 

        _vaultHarvest(); //Perform the harvest of earned reward tokens

        for (uint i; i < config.earnedLength(); i++) { //In case of multiple reward vaults, process each reward token
            (IERC20 earnedToken, uint dust) = config.earned(i);

            //Don't swap targetWant (goes to maximizer) or want (kept)
            if (earnedToken != targetWant && earnedToken != _wantToken) {
                uint256 earnedAmt = earnedToken.balanceOf(address(this));
                if (earnedAmt > dust) { //Only swap if enough has been earned
                    IERC20[] memory path;
                    bool toWeth;
                    if (config.isPairStake()) {
                        (IERC20 token0, IERC20 token1) = config.token0And1();
                        (toWeth, path) = wethOnPath(earnedToken, token0);
                        (bool toWethToken1,) = wethOnPath(earnedToken, token1);
                        toWeth = toWeth && toWethToken1;
                    } else {
                        (toWeth, path) = wethOnPath(earnedToken, _wantToken);
                    }
                    if (toWeth) safeSwap(earnedAmt, path); //swap to the native gas token if it's on the path
                    else swapToWantToken(earnedAmt, earnedToken);
                }
            }
        }

        uint wantBalance = _wantToken.balanceOf(address(this));        
        if (wantBalance > config.wantDust()) {
            wantAmt = fees.payTokenFeePortion(_wantToken, wantBalance - wantAmt) + wantAmt; //fee portion on newly obtained want tokens
            success = true;
        }
        if (unwrapAllWeth()) {
            fees.payEthPortion(address(this).balance); //pays the fee portion
            uint wethAmt = address(this).balance;
            wrapAllEth();
            swapToWantToken(wethAmt, config.weth());
            success = true;
        }
        uint targetWantBalance = targetWant.balanceOf(address(this));        
        if (targetWantBalance > targetWantDust) {

            targetWantAmt = fees.payTokenFeePortion(targetWant, targetWantBalance - targetWantAmt) + targetWantAmt;
            success = true;
            
            try IVaultHealer(msg.sender).maximizerDeposit(config.vid(), targetWantAmt, "") {} //deposit the rest, and any targetWant tokens
            catch {
                emit Strategy_MaximizerDepositFailure();
            }
        }

        __wantLockedTotal = config.wantToken().balanceOf(address(this)) + _farm();
    }

}