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
            IWETH weth = router.WETH();
            safeSwap(s, feeEarnedAmt, _earnedToken, weth, address(this));
			
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
        Settings memory s,
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

        IUniRouter router = s.router;
        IERC20[] memory path = s.magnetite.findAndSavePath(address(router), _tokenA, _tokenB);

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

        if (s.feeOnTransfer) {
            router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                _amountIn, 
                router.getAmountsOut(_amountIn, cleanedUpPath)[cleanedUpPath.length - 2] * s.slippageFactor / 10000,
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