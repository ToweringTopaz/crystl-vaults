// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "./BaseStrategy.sol";
import "./MaximizerStrategy.sol";

//Standard v3 Strategy
contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using StrategyConfig for StrategyConfig.MemPointer;
    using Fee for Fee.Data[3];
    using VaultChonk for IVaultHealer;

    IStrategy immutable _maximizerImplementation;

    constructor() {
        _maximizerImplementation = _deployMaximizerImplementation();
            uint256 earnedAmt = earnedToken.balanceOf(address(this));
            if (earnedAmt > dust) { //don't waste gas swapping minuscule rewards
                success = true; //We have something worth compounding

                if (earnedToken != targetWant) safeSwap(earnedAmt, earnedToken, config.weth()); //swap to the native gas token if not the targetwant token
            }
        }
        if (!success) return (false, _wantLockedTotal());

        //pay fees on new targetWant tokens
        targetWantAmt = fees.payTokenFeePortion(targetWant, targetWant.balanceOf(address(this)) - targetWantAmt) + targetWantAmt;

        if (config.isMaximizer() && (targetWantAmt > 0 || unwrapAllWeth())) {
            fees.payEthPortion(address(this).balance); //pays the fee portion
            try IVaultHealer(msg.sender).maximizerDeposit{value: address(this).balance}(config.vid(), targetWantAmt, "") { //deposit the rest, and any targetWant tokens
                return (true, _wantLockedTotal());
            }
            catch {  //compound want instead if maximizer doesn't work
                success = false;
            }
        }
        //standard autocompound behavior
        wrapAllEth();
        IWETH weth = config.weth();
        uint wethAmt = weth.balanceOf(address(this));
        if (wethAmt > WETH_DUST && success) { //success is only false here if maximizerDeposit was attempted and failed
            wethAmt = fees.payWethPortion(weth, wethAmt); //pay fee portion
            swapToWantToken(wethAmt, weth);
        }
        __wantLockedTotal = _wantToken.balanceOf(address(this)) + _farm();
    }

    function _deployMaximizerImplementation() internal virtual returns (IStrategy) {
        return new MaximizerStrategy();
    }

    function getMaximizerImplementation() external virtual override view returns (IStrategy) {
        return _maximizerImplementation;
    }

    function sellUnwanted(IERC20 tokenOut, uint amount) internal {
        IERC20[] memory path;
        bool toWeth;
        if (config.isPairStake()) {
            (IERC20 token0, IERC20 token1) = config.token0And1();
            (toWeth, path) = wethOnPath(tokenOut, token0);
            (bool toWethToken1,) = wethOnPath(tokenOut, token1);
            toWeth = toWeth && toWethToken1;
        } else {
            (toWeth, path) = wethOnPath(tokenOut, config.wantToken());
        }
        if (toWeth) safeSwap(amount, path); //swap to the native gas token if it's on the path
        else swapToWantToken(amount, tokenOut);
    }



    function _earn(Fee.Data[3] calldata fees, address, bytes calldata) internal virtual override returns (bool success, uint256 __wantLockedTotal) {
        _sync();        
        IERC20 _wantToken = config.wantToken();
		uint wantAmt = _wantToken.balanceOf(address(this)); 

        _vaultHarvest(); //Perform the harvest of earned reward tokens
        
        for (uint i; i < config.earnedLength(); i++) { //In case of multiple reward vaults, process each reward token
            (IERC20 earnedToken, uint dust) = config.earned(i);

            if (earnedToken != _wantToken) {
                uint256 earnedAmt = earnedToken.balanceOf(address(this));
                //don't waste gas swapping minuscule rewards
                if (earnedAmt > dust) sellUnwanted(earnedToken, earnedAmt);
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
        __wantLockedTotal = _wantToken.balanceOf(address(this)) + (success ? _farm() : _vaultSharesTotal());
    }

}