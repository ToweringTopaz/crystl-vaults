 // SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./libs/HardMath.sol";
import "./libs/LibQuartz.sol";
import "./BaseStrategy.sol";
import "./libs/Vault.sol";
import "./libs/PrismLibrary.sol";
import {SafeERC20Upgradeable as SafeERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {AddressUpgradeable as Address} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "./libs/IVaultHealer.sol";
import "hardhat/console.sol";

//Contains the strategy's functions related to swapping, earning, etc.
abstract contract BaseStrategySwapLogic is BaseStrategy {
    using SafeERC20 for IERC20;

    uint constant FEE_MAX = 10000;

    function isMaximizer() public view returns (bool) {
        return address(targetVault) != address(0);
    }

    function _wantBalance() internal override view returns (uint256) {
        return wantToken.balanceOf(address(this));
    }

    function earn(Fee.Data[3] memory fees) external returns (bool success, uint256 _wantLockedTotal) {
        uint wantBalanceBefore = _wantBalance(); //Don't sell starting want balance (anti-rug)

        _vaultHarvest(); // Harvest farm tokens
        // console.log("BSSL - A");
        uint dust = settings.dust; //minimum number of tokens to bother trying to compound
        
        success;
        for (uint i; address(earned[i]) != address(0); i++) { //Process each earned token, whether it's 1, 2, or 8. 
            // console.log("BSSL - B");

            IERC20 earnedToken = earned[i];
            uint256 earnedAmt = earnedToken.balanceOf(address(this));
            if (earnedToken == wantToken)
                // console.log("BSSL - B");
                earnedAmt -= wantBalanceBefore; //ignore pre-existing want tokens
                
            if (earnedAmt > dust) {
                // console.log("BSSL - C");
                success = true; //We have something worth compounding
                earnedAmt = distribute(fees, earnedToken, earnedAmt); // handles all fees for this earned token

                if (address(lpToken[1]) == address(0)) { //single stake
                    // console.log("BSSL - D");

                    safeSwap(earnedAmt, earnedToken, lpToken[0], address(this));
                } else {
                    // console.log("BSSL - E");
                    safeSwap(earnedAmt / 2, earnedToken, lpToken[0], address(this));
                    safeSwap(earnedAmt / 2, earnedToken, lpToken[1], address(this));
                }
            }
        }
        //lpTokenLength == 1 means single-stake, not LP
        if (success) {

            if (isMaximizer()) {
                // console.log("BSSL - in Maximizer conditional");
                IERC20 crystlToken = maximizerRewardToken; //todo: change this from a hardcoding
                uint256 crystlBalance = crystlToken.balanceOf(address(this));
                console.log("crystlBalance");
                console.log(crystlBalance);

                IVaultHealer(msg.sender).deposit(targetVid, crystlBalance);
                // console.log("BSSL - deposited to vaultHealer");
            } else {
                // console.log("BSSL - second half of Maximizer conditional");
                if (address(lpToken[1]) != address(0)) {
                    // console.log("BSSL - past if statement in Maximizer conditional");
                    // Get want tokens, ie. add liquidity
                    LibQuartz.optimalMint(IUniPair(address(wantToken)), lpToken[0], lpToken[1]);
                }
                // console.log("BSSL - about to farm");
                _farm();
            }
        }
        _wantLockedTotal = wantLockedTotal();
    }
    
    //Safely deposits want tokens in farm
    function _farm() override internal {
        uint256 wantAmt = _wantBalance();
        if (wantAmt == 0) return;
        
        uint256 sharesBefore = vaultSharesTotal();
        
        _vaultDeposit(wantAmt); //approves the transfer then calls the pool contract to deposit
        // console.log("BSSL - deposited to vault");
        uint256 sharesAfter = vaultSharesTotal();
        
        //including settings.dust to reduce the chance of false positives
        //safety check, will fail if there's a deposit fee rugpull or serious bug taking deposits
        require(sharesAfter + _wantBalance() + settings.dust >= (sharesBefore + wantAmt) * settings.slippageFactor / 10000,
            "High vault deposit slippage");
        return;
    }

    function distribute(Fee.Data[3] memory fees, IERC20 _earnedToken, uint256 _earnedAmt) internal returns (uint earnedAmt) {

        earnedAmt = _earnedAmt;
        IUniRouter router = settings.router;

        uint feeTotalRate;
        for (uint i; i < 3; i++) {
            feeTotalRate += Fee.rate(fees[i]);
        }
        
        if (feeTotalRate > 0) {
            uint256 feeEarnedAmt = _earnedAmt * feeTotalRate / FEE_MAX;
            earnedAmt -= feeEarnedAmt;
            uint nativeBefore = address(this).balance;
            safeSwap(feeEarnedAmt, _earnedToken, router.WETH(), address(this));
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
        IUniRouter router = settings.router;
        // console.log("BSSL - just before magnetite call");  
        IERC20[] memory path = settings.magnetite.findAndSavePath(address(router), _tokenA, _tokenB);
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
        uint256 amountOut = amounts[amounts.length - 1] * settings.slippageFactor / 10000;
        // console.log("BSSL - got here");

        //allow swap.router to pull the correct amount in
        IERC20(_tokenA).safeIncreaseAllowance(address(settings.router), _amountIn);
        bool feeOnTransfer = settings.feeOnTransfer;

        if (_tokenB != router.WETH() ) {
            if (feeOnTransfer) { //reflect mode on
                // console.log("BSSL - 12");
                router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    _amountIn, amountOut, cleanedUpPath, _to, block.timestamp);
            } else { //reflect mode off
                // console.log("BSSL - 13");
                router.swapExactTokensForTokens(
                    _amountIn, amountOut, cleanedUpPath, _to, block.timestamp);
            }
        } else {
            if (feeOnTransfer) { //reflect mode on
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