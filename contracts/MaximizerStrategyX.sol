// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "./MaximizerStrategy.sol";

contract MaximizerStrategyX is MaximizerStrategy {
    using StrategyConfig for StrategyConfig.MemPointer;
    using Fee for Fee.Data[3];

    function _earn(Fee.Data[3] calldata fees, address, bytes calldata) internal override returns (bool success) {
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
                if (earnedAmt > dust) sellUnwanted(earnedToken, earnedAmt);
            }
        }

        uint wantHarvested = _wantToken.balanceOf(address(this)) - wantAmt;
        if (wantHarvested > config.wantDust()) {
            wantAmt = fees.payTokenFeePortion(_wantToken, wantHarvested) + wantAmt; //fee portion on newly obtained want tokens
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

        _farm();
    }

}
