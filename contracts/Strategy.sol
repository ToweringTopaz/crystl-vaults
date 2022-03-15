// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./BaseStrategy.sol";
import "./libraries/LibQuartz.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "hardhat/console.sol";
//This is a strategy contract which can be expected to support 99% of pools. Tactic contracts provide the pool interface.
contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using StrategyConfig for StrategyConfig.MemPointer;
    using Fee for Fee.Data[3];
	
	error TotalSlippageWithdrawal(); //nothing to withdraw after slippage
	error DustDeposit(uint256 wantAdded); //Deposit amount is insignificant after slippage

    constructor(address _vaultHealer) BaseStrategy(_vaultHealer) {}

    function earn(Fee.Data[3] calldata fees, address, bytes calldata) external virtual getConfig onlyVaultHealer returns (bool success, uint256 __wantLockedTotal) {
        //console.log("earn1");
        (IERC20 _wantToken,) = config.wantToken();
        uint wantBalanceBefore = _wantToken.balanceOf(address(this)); //Don't sell starting want balance (anti-rug)
        //console.log("earn2");
        _vaultHarvest();

        IWETH weth = config.weth();
        uint earnedLength = config.earnedLength();

        for (uint i; i < earnedLength; i++) {
            (IERC20 earnedToken, uint dust) = config.earned(i);
            //console.log("earnedToken: ", address(earnedToken));

            uint256 earnedAmt = earnedToken.balanceOf(address(this));
            //console.log("earnedAmt: ", earnedAmt);
            if (earnedToken == _wantToken) earnedAmt -= wantBalanceBefore; //ignore pre-existing want tokens
            //console.log("earnedAmt: ", earnedAmt);
            if (earnedAmt < dust) continue; //not enough of this token earned to continue with a swap
            
            success = true; //We have something worth compounding
            //console.log("earn3");
            safeSwap(earnedAmt, earnedToken, weth); //swap all earned tokens to weth (native token)
            //console.log("earn4");
        }
        if (!success) return (false, _wantLockedTotal()); //Nothing to do because harvest
        //console.log("earn5");
        uint wethAdded = weth.balanceOf(address(this));
        if (_wantToken == weth) wethAdded -= wantBalanceBefore; //ignore pre-existing want tokens
        //console.log("earn6");
        if (config.isMaximizer()) {
            //console.log("earnm1");
            weth.withdraw(wethAdded); //unwrap wnative token
            uint ethToTarget = fees.payEthPortion(address(this).balance); //pays the fee portion, returns the amount after fees
            //console.log("earnm2");
            IVaultHealer(msg.sender).maximizerDeposit{value: ethToTarget}(config.vid(), 0, ""); //deposit the rest
            //console.log("earnm3");
        } else {
            //console.log("earnc1");
            wethAdded = fees.payWethPortion(weth, wethAdded); //pay fee portion

            if (config.isPairStake()) {
                (IERC20 token0, IERC20 token1) = config.token0And1();
                safeSwap(wethAdded / 2, weth, token0);
                safeSwap(wethAdded / 2, weth, token1);
                LibQuartz.optimalMint(IUniPair(address(_wantToken)), token0, token1);
                //console.log("earnc1a");
            } else {
                safeSwap(wethAdded, weth, _wantToken);
                //console.log("earnc1b");
            }
            //console.log("earn7");
            _farm();
            //console.log("earn8");
        }

        __wantLockedTotal = _wantLockedTotal();
    }

    //VaultHealer calls this to add funds at a user's direction. VaultHealer manages the user shares
    function deposit(uint256 _wantAmt, uint256 _sharesTotal, bytes calldata) external virtual payable getConfig onlyVaultHealer returns (uint256 wantAdded, uint256 sharesAdded) {
        (IERC20 _wantToken, uint dust) = config.wantToken();
        uint wantBal = _wantToken.balanceOf(address(this));
        uint wantLockedBefore = wantBal + _vaultSharesTotal();

        if (msg.value > 0) {
            IWETH weth = config.weth();
            weth.deposit{value: msg.value}();
            if (config.isPairStake()) {
                (IERC20 token0, IERC20 token1) = config.token0And1();
                safeSwap(msg.value / 2, weth, token0);
                safeSwap(msg.value / 2, weth, token1);
                LibQuartz.optimalMint(IUniPair(address(_wantToken)), token0, token1);
            } else {
                safeSwap(msg.value, weth, _wantToken);
            }
        }

        //Before calling deposit here, the vaulthealer records how much the user deposits. Then with this
        //call, the strategy tells the vaulthealer to proceed with the transfer. This minimizes risk of
        //a rogue strategy 
        if (_wantAmt > 0) IVaultHealer(msg.sender).executePendingDeposit(address(this), uint192(_wantAmt));
        _farm(); //deposits the tokens in the pool
        // Proper deposit amount for tokens with fees, or vaults with deposit fees

        wantAdded = _wantToken.balanceOf(address(this)) + _vaultSharesTotal() - wantLockedBefore;
        sharesAdded = wantAdded;
        if (_sharesTotal > 0) { 
            sharesAdded = Math.ceilDiv(sharesAdded * _sharesTotal, wantLockedBefore);
        }
        if (wantAdded < dust) revert DustDeposit(wantAdded);
    }


    //Correct logic to withdraw funds, based on share amounts provided by VaultHealer
    function withdraw(uint _wantAmt, uint _userShares, uint _sharesTotal, bytes calldata) external virtual getConfig onlyVaultHealer returns (uint sharesRemoved, uint wantAmt) {
        (IERC20 _wantToken, uint dust) = config.wantToken();
        uint wantBal = _wantToken.balanceOf(address(this)); 
        uint wantLockedBefore = wantBal + _vaultSharesTotal();
        uint256 userWant = _userShares * wantLockedBefore / _sharesTotal; //User's balance, in want tokens
        
        // user requested all, very nearly all, or more than their balance, so withdraw all
        unchecked { //overflow is caught and handled in the second condition
            if (_wantAmt + dust > userWant || _wantAmt + dust < _wantAmt) {
				_wantAmt = userWant;
            }
        }

		uint withdrawSlippage;
        if (_wantAmt > wantBal) {
            _vaultWithdraw(_wantToken, _wantAmt - wantBal); //Withdraw from the masterchef, staking pool, etc.
            wantBal = _wantToken.balanceOf(address(this));
			uint wantLockedAfter = wantBal + _vaultSharesTotal();
			
			//Account for reflect, pool withdraw fee, etc; charge these to user
			withdrawSlippage = wantLockedAfter < wantLockedBefore ? wantLockedBefore - wantLockedAfter : 0;
		} else {
			withdrawSlippage = 0;
		}
		
		//Calculate shares to remove
        sharesRemoved = Math.ceilDiv(
            (_wantAmt + withdrawSlippage) * _sharesTotal,
            wantLockedBefore
        );
		
        //Get final withdrawal amount
        if (sharesRemoved > _userShares) {
            sharesRemoved = _userShares;
        }
		wantAmt = sharesRemoved * wantLockedBefore / _sharesTotal;
		if (wantAmt > withdrawSlippage) {
			wantAmt -= withdrawSlippage;
			if (wantAmt > wantBal) wantAmt = wantBal;
		} else {
			revert TotalSlippageWithdrawal(); //nothing to withdraw after slippage
		}

        return (sharesRemoved, wantAmt);

    }

}