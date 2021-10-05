// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./libs/PrismLibrary2.sol";

import "./BaseStrategy.sol";
import "./Magnetite.sol";
import "./BaseStrategyVaultHealer.sol";

//Extends swap logic with maximizer functionality
abstract contract BaseStrategyMaxi is BaseStrategyVaultHealer {
    using SafeERC20 for IERC20;

    function _earn(address _to) internal override whenEarnIsReady {
        
        //Starting want balance which is not to be touched (anti-rug)
        uint wantBalanceBefore = _wantBalance();
        
        // Harvest farm tokens
        _vaultHarvest();
    
        // Converts farm tokens into want tokens
        //Try/catch means we carry on even if compounding fails for some reason
        try this._swapEarnedToWant(_to, wantBalanceBefore) returns (bool success) {
            if (success) {
                lastGainBlock = block.number; //So frontend can see if a vault no longer actually gains any value
                _farm(); //deposit the want tokens so they can begin earning
            }
        } catch {}
        
        lastEarnBlock = block.number;
    }

    //Called externally by this contract so that if it fails, the error is caught rather than blocking
    function _swapEarnedToWant(address _to, uint256 _wantBal) external onlyThisContract returns (bool success) {

        for (uint i; i < earnedLength; i++ ) { //Process each earned token, whether it's 1, 2, or 8.
            address earnedAddress = earned[i];
            
            uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));
            if (earnedAddress == wantAddress) earnedAmt -= _wantBal; //ignore pre-existing want tokens
            
            uint dust = settings.dust; //minimum number of tokens to bother trying to compound
    
            if (earnedAmt > dust) {
                success = true; //We have something worth compounding
                earnedAmt = distributeFees(earnedAddress, earnedAmt, _to); // handles all fees for this earned token
                
                // Swap half earned to token0, half to token1 (or split evenly however we must, for balancer etc)
                // Same logic works if lpTokenLength == 1 ie single-staking pools
                for (uint j; j < lpTokenLength; i++) {
                    _safeSwap(earnedAmt / lpTokenLength, earnedAddress, lpToken[j], address(this));
                }
            }
        }
        //lpTokenLength == 1 means single-stake, not LP
        if (success && lpTokenLength > 1) {
            // Get want tokens, ie. add liquidity
            PrismLibrary2.optimalMint(wantAddress, lpToken[0], lpToken[1]);
        }
    }
    
    //Checks whether a swap is burning crystl, and if so, tracks it
    modifier updateBurn(address _token, address _to) {
        if (_token == CRYSTL && _to == settings.buybackFeeReceiver) {
            uint burnedBefore = IERC20(CRYSTL).balanceOf(settings.buybackFeeReceiver);
            _;
            burnedAmount += IERC20(CRYSTL).balanceOf(settings.buybackFeeReceiver) - burnedBefore;
        } else {
            _;
        }
    }
    
    function _safeSwap(
        uint256 _amountIn,
        address _tokenA,
        address _tokenB,
        address _to
    ) internal updateBurn(_tokenB, _to) {
        //Handle one-token paths which are simply a transfer
        if (_tokenA == _tokenB) {
            //swapping same token to self? do nothing
            if (_to == address(this))
                return;
            IERC20(_tokenA).safeTransfer(_to, _amountIn);
            return;
        }
        address[] memory path = magnetite().findAndSavePath(address(settings.router), _tokenA, _tokenB);
        
        uint256[] memory amounts = settings.router.getAmountsOut(_amountIn, path);
        uint256 amountOut = amounts[amounts.length - 1] * settings.slippageFactor / 10000;
        
        IERC20(_tokenA).safeIncreaseAllowance(address(settings.router), _amountIn);
        if (settings.feeOnTransfer) {
            settings.router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                _amountIn,
                amountOut,
                path,
                _to,
                block.timestamp + 600
            );
        } else {
            settings.router.swapExactTokensForTokens(
                _amountIn,
                amountOut,
                path,
                _to,
                block.timestamp + 600
            );
        }
    }
    
    function distributeFees(address _earnedAddress, uint256 _earnedAmt, address _to) internal returns (uint earnedAmt) {
        earnedAmt = _earnedAmt;
        
        uint controllerFee = settings.controllerFee;
        uint rewardRate = settings.rewardRate;
        uint buybackRate = settings.buybackRate;
        
        // To pay for earn function
        if (controllerFee > 0) {
            uint256 fee = _earnedAmt * controllerFee / FEE_MAX;
            _safeSwap(fee, _earnedAddress, WNATIVE, _to);
            earnedAmt -= fee;
        }
        //distribute rewards
        if (rewardRate > 0) {
            uint256 fee = _earnedAmt * rewardRate / FEE_MAX;
            if (_earnedAddress == CRYSTL)
                IERC20(_earnedAddress).safeTransfer(settings.rewardFeeReceiver, fee);
            else
                _safeSwap(fee, _earnedAddress, DAI, settings.rewardFeeReceiver);

            earnedAmt -= fee;
        }
        //burn crystl
        if (buybackRate > 0) {
            uint256 buyBackAmt = _earnedAmt * buybackRate / FEE_MAX;
            _safeSwap(buyBackAmt, _earnedAddress, CRYSTL, settings.buybackFeeReceiver);
            earnedAmt -= buyBackAmt;
        }
        
        return earnedAmt;
    }
    
    //Safely deposits want tokens in farm
    function _farm() override internal {
        uint256 wantAmt = _wantBalance();
        if (wantAmt == 0) return;
        
        uint256 sharesBefore = vaultSharesTotal();
        
        _vaultDeposit(wantAmt); //approves transfer then calls the pool contract to deposit
        uint256 sharesAfter = vaultSharesTotal();
        
        //including settings.dust to reduce the chance of false positives
        require(sharesAfter + _wantBalance() + settings.dust >= sharesBefore + wantAmt * settings.slippageFactor / 10000,
            "High vault deposit slippage"); //safety check, will fail if there's a deposit fee rugpull
        return;
    }
}