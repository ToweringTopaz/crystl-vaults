 // SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./libs/HardMath.sol";
import "./libs/LibQuartz.sol";
import "./libs/IVaultHealer.sol";
import "./libs/Vault.sol";
import {AddressUpgradeable as Address} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "./BaseStrategy.sol";

//Contains the strategy's functions related to swapping, earning, etc.
abstract contract BaseStrategySwapLogic is BaseStrategy {
    using SafeERC20 for IERC20;

    uint constant FEE_MAX = 10000;

    function earn(Fee.Data[3] memory fees) external returns (bool success, uint256 _wantLockedTotal) {
        Settings memory s = getSettings();
        IERC20 wantToken = s.wantToken;

        uint wantBalanceBefore = wantToken.balanceOf(address(this)); //Don't sell starting want balance (anti-rug)

        Tactics.harvest(s.tacticsA, s.tacticsB); // Harvest farm tokens
        
        for (uint i; i < s.earned.length; i++) { //Process each earned token, whether it's 1, 2, or 8. 

            IERC20 earnedToken = s.earned[i];
            uint256 earnedAmt = earnedToken.balanceOf(address(this));
            if (earnedToken == wantToken)
                earnedAmt -= wantBalanceBefore; //ignore pre-existing want tokens

            if (earnedAmt > s.dust) { //minimum number of tokens to bother trying to compound
                success = true; //We have something worth compounding
                earnedAmt = distribute(s, fees, earnedToken, earnedAmt); // handles all fees for this earned token

                if (address(s.lpToken[1]) == address(0)) { //single stake

                    safeSwap(s, earnedAmt, earnedToken, s.lpToken[0], address(this));
                } else {
                    safeSwap(s, earnedAmt / 2, earnedToken, s.lpToken[0], address(this));
                    safeSwap(s, earnedAmt / 2, earnedToken, s.lpToken[1], address(this));
                }
            }
        }
        //lpTokenLength == 1 means single-stake, not LP
        if (success) {

            if (s.targetVid != 0) { //is a maximizer
                (IERC20 targetWant,) = IVaultHealer(msg.sender).vaultInfo(s.targetVid);
                uint256 crystlBalance = targetWant.balanceOf(address(this));

                IVaultHealer(msg.sender).deposit(s.targetVid, crystlBalance);
            } else {
                if (address(s.lpToken[1]) != address(0)) {
                    // Get want tokens, ie. add liquidity
                    LibQuartz.optimalMint(IUniPair(address(wantToken)), s.lpToken[0], s.lpToken[1]);
                }
                _farm(s);
            }
        }
        _wantLockedTotal = s.wantToken.balanceOf(address(this)) + _vaultSharesTotal(s);
    }
    
    //Safely deposits want tokens in farm
    function _farm(Settings memory s) override internal {
        uint256 wantAmt = s.wantToken.balanceOf(address(this));
        if (wantAmt == 0) return;
        
        uint256 sharesBefore = _vaultSharesTotal(s);
        
        _vaultDeposit(s, wantAmt); //approves the transfer then calls the pool contract to deposit
        // console.log("BSSL - deposited to vault");
        uint256 sharesAfter = _vaultSharesTotal(s);
        
        //including settings.dust to reduce the chance of false positives
        //safety check, will fail if there's a deposit fee rugpull or serious bug taking deposits
        require(sharesAfter + s.wantToken.balanceOf(address(this)) + s.dust >= (sharesBefore + wantAmt) * s.slippageFactor / 10000,
            "High vault deposit slippage");
        return;
    }

    function distribute(Settings memory s, Fee.Data[3] memory fees, IERC20 _earnedToken, uint256 _earnedAmt) internal returns (uint earnedAmt) {

        earnedAmt = _earnedAmt;
        IUniRouter router = s.router;

        uint feeTotalRate;
        for (uint i; i < 3; i++) {
            feeTotalRate += Fee.rate(fees[i]);
        }
        
        if (feeTotalRate > 0) {
            uint256 feeEarnedAmt = _earnedAmt * feeTotalRate / FEE_MAX;
            earnedAmt -= feeEarnedAmt;
            uint nativeBefore = address(this).balance;
            safeSwap(s, feeEarnedAmt, _earnedToken, router.WETH(), address(this));
            uint feeNativeAmt = address(this).balance - nativeBefore;
            for (uint i; i < 3; i++) {
                (address receiver, uint rate) = Fee.receiverAndRate(fees[i]);
                if (receiver == address(0) || rate == 0) break;
                (bool success,) = receiver.call{value: feeNativeAmt * rate / feeTotalRate}("");
                require(success, "Strategy: Transfer failed");
            }
        }
    }

    function safeSwap(
        Settings memory s,
        uint256 _amountIn,
        IERC20 _tokenA,
        IERC20 _tokenB,
        address _to
    ) internal {
        // console.log("BSSL - in SafeSwap");
        //Handle one-token paths which are simply a transfer
        if (_tokenA == _tokenB) {
            // console.log("BSSL - doing a transfer");
            if (_to != address(this)) //skip transfers to self
                _tokenA.safeTransfer(_to, _amountIn);
            return;
        }
        IUniRouter router = s.router;
        // console.log("BSSL - just before magnetite call");  
        IERC20[] memory path = s.magnetite.findAndSavePath(address(router), _tokenA, _tokenB);
        // console.log("BSSL - came out of magnetite");      

        /////////////////////////////////////////////////////////////////////////////////////////////
        //this code snippet below could be removed if findAndSavePath returned a right-sized array //
        uint256 counter=0;
        for (counter; counter<path.length; counter++){
            if (address(path[counter]) == address(0)) break;
        }
        IERC20[] memory cleanedUpPath = new IERC20[](counter);
        for (uint256 i=0; i<counter; i++) {
            cleanedUpPath[i] =path[i];
        }
        // console.log("BSSL - got here");
        //this code snippet above could be removed if findAndSavePath returned a right-sized array


        uint256[] memory amounts = router.getAmountsOut(_amountIn, cleanedUpPath);
        uint256 amountOut = amounts[amounts.length - 1] * s.slippageFactor / 10000;
        // console.log("BSSL - got here");

        //allow swap.router to pull the correct amount in
        IERC20(_tokenA).safeIncreaseAllowance(address(router), _amountIn);

        if (_tokenB != router.WETH() ) {
            if (s.feeOnTransfer > 0) { //reflect mode on
                // console.log("BSSL - 12");
                router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    _amountIn, amountOut, cleanedUpPath, _to, block.timestamp);
            } else { //reflect mode off
                // console.log("BSSL - 13");
                router.swapExactTokensForTokens(
                    _amountIn, amountOut, cleanedUpPath, _to, block.timestamp);
            }
        } else {
            if (s.feeOnTransfer > 0) { //reflect mode on
                // console.log("BSSL - 14");
                router.swapExactTokensForETHSupportingFeeOnTransferTokens(
                    _amountIn, amountOut, cleanedUpPath, _to, block.timestamp);
            } else { //reflect mode off
                // console.log("BSSL - 15");
                router.swapExactTokensForETH(
                    _amountIn ,amountOut, cleanedUpPath, _to, block.timestamp);
            }            
        }
    }
    receive() external payable {}
}