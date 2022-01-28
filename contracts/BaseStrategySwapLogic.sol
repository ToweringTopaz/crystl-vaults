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
        uint dust = settings.dust; //minimum number of tokens to bother trying to compound
        
        for (uint i; address(earned[i]) != address(0); i++) { //Process each earned token

            IERC20 earnedToken = earned[i];
            uint256 earnedAmt = earnedToken.balanceOf(address(this));
            if (earnedToken == wantToken)
                earnedAmt -= wantBalanceBefore; //ignore pre-existing want tokens

            if (earnedAmt > dust) {
                success = true; //We have something worth compounding
                earnedAmt = distribute(fees, earnedToken, earnedAmt); // handles all fees for this earned token

                if (address(lpToken[1]) == address(0)) { //single stake

                    safeSwap(earnedAmt, earnedToken, lpToken[0], address(this));
                } else {
                    safeSwap(earnedAmt / 2, earnedToken, lpToken[0], address(this));
                    safeSwap(earnedAmt / 2, earnedToken, lpToken[1], address(this));
                }
            }
        }
        //lpTokenLength == 1 means single-stake, not LP
        if (success) {

            if (isMaximizer()) {
                uint256 crystlBalance = maximizerRewardToken.balanceOf(address(this));

                IVaultHealer(msg.sender).deposit(targetVid, crystlBalance);
            } else {
                if (address(lpToken[1]) != address(0)) {
                    // Get want tokens, ie. add liquidity
                    LibQuartz.optimalMint(IUniPair(address(wantToken)), lpToken[0], lpToken[1]);
                }
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
            IWETH weth = router.WETH();
            safeSwap(feeEarnedAmt, _earnedToken, weth, address(this));
            uint feeNativeAmt = address(this).balance - nativeBefore;

            weth.withdraw(weth.balanceOf(address(this)));
            for (uint i; i < 3; i++) {
                (address receiver, uint rate) = Fee.receiverAndRate(fees[i]);
                if (receiver == address(0) || rate == 0) break;
                (bool success,) = receiver.call{value: feeNativeAmt * rate / feeTotalRate, gas: 0x40000}("");
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
        //Handle one-token paths which are simply a transfer
        if (_tokenA == _tokenB) {
            if (_to != address(this)) //skip transfers to self
                _tokenA.safeTransfer(_to, _amountIn);
            return;
        }
        IUniRouter router = settings.router;
        IERC20[] memory path = settings.magnetite.findAndSavePath(address(router), _tokenA, _tokenB);

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
        //this code snippet above could be removed if findAndSavePath returned a right-sized array

        //allow swap.router to pull the correct amount in
        IERC20(_tokenA).safeIncreaseAllowance(address(router), _amountIn);

        if (settings.feeOnTransfer) {
            router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                _amountIn, 
                router.getAmountsOut(_amountIn, cleanedUpPath)[cleanedUpPath.length - 2] * settings.slippageFactor / 10000,
                cleanedUpPath,
                _to, 
                block.timestamp
            );
        } else {
            router.swapExactTokensForTokens(_amountIn, 0, cleanedUpPath, _to, block.timestamp);                
        }
    }

    receive() external payable {}
}