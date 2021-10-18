// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./PrismLibrary.sol";
import "./LibVaultConfig.sol";
import "./FullMath.sol";

//Functions specific to the strategy code
library LibVaultSwaps {
    using SafeERC20 for IERC20;
    using Address for address;
    
    //For tracking earned/burned
    struct VaultStats {
        uint128 totalEarned;
        uint128 totalBurned;
    }
    
    IERC20 constant WNATIVE_DEFAULT = IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    uint256 constant FEE_MAX = 10000; // 100 = 1% : basis points
    
    function distribute(VaultFees storage fees, VaultSettings storage settings, VaultStats storage stats, IERC20 _earnedToken, uint256 _earnedAmt, address _to) internal returns (uint earnedAmt) {
        uint burnedBefore = IERC20(fees.burn.token).balanceOf(fees.burn.receiver);

        earnedAmt = _earnedAmt;
        // To pay for earn function
        uint256 fee = _earnedAmt * fees.earn.rate / FEE_MAX;
        safeSwap(settings, fee, _earnedToken, fees.earn.token, _to);
        earnedAmt -= fee; 
        //distribute rewards
        fee = _earnedAmt * fees.reward.rate / FEE_MAX;
        safeSwap(settings, fee, _earnedToken, _earnedToken == fees.burn.token ? fees.burn.token : fees.reward.token, fees.reward.receiver);
        earnedAmt -= fee;
        //burn crystl
        fee = _earnedAmt * fees.burn.rate / FEE_MAX;
        safeSwap(settings, fee, _earnedToken, fees.burn.token, fees.burn.receiver);
        earnedAmt -= fee;

        unchecked { //overflow ok albeit unlikely
            stats.totalEarned += uint128(earnedAmt);
            stats.totalBurned += uint128(IERC20(fees.burn.token).balanceOf(fees.burn.receiver) - burnedBefore);
        }
    }

    function safeSwap(
        VaultSettings storage settings,
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
        address[] memory path = settings.magnetite.findAndSavePath(address(settings.router), address(_tokenA), address(_tokenB));
        
        uint256[] memory amounts = settings.router.getAmountsOut(_amountIn, path);
        uint256 amountOut = amounts[amounts.length - 1] * settings.slippageFactor / 10000;
        
        //allow router to pull the correct amount in
        IERC20(_tokenA).safeIncreaseAllowance(address(settings.router), _amountIn);
        
        if (_tokenB != wnative(settings.router) || _to.isContract() ) {
            if (settings.feeOnTransfer) { //reflect mode on
                settings.router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    _amountIn, amountOut, path, _to, block.timestamp);
            } else { //reflect mode off
                settings.router.swapExactTokensForTokens(
                    _amountIn,amountOut, path, _to, block.timestamp);
            }
        } else { //Non-contract address (extcodesize zero) receives native ETH
            if (settings.feeOnTransfer) { //reflect mode on
                settings.router.swapExactTokensForETHSupportingFeeOnTransferTokens(
                    _amountIn, amountOut, path, _to, block.timestamp);
            } else { //reflect mode off
                settings.router.swapExactTokensForETH(
                    _amountIn,amountOut, path, _to, block.timestamp);
            }            
        }

    }
    
    //based on liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);    
    function optimalMint(IERC20 pair, IERC20 tokenA, IERC20 tokenB) internal returns (uint liquidity) {
        (address token0, address token1) = PrismLibrary.sortTokens(address(tokenA), address(tokenB));

        (uint112 reserve0, uint112 reserve1,) = IUniPair(address(pair)).getReserves();
        uint totalSupply = pair.totalSupply();
        
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));

        uint liquidity0 = balance0 * totalSupply / reserve0;
        uint liquidity1 = balance1 * totalSupply / reserve1;

        if (liquidity0 < liquidity1) {
            balance1 = reserve1 * balance0 / reserve0;
        } else if (liquidity1 < liquidity0) {
            balance0 = reserve0 * balance1 / reserve1;
        }

        IERC20(token0).safeTransfer(address(pair), balance0);
        IERC20(token1).safeTransfer(address(pair), balance1);
        liquidity = IUniPair(address(pair)).mint(address(this));
    }
    
    function wnative(IUniRouter02 router) private pure returns (IERC20) {
        try IUniRouter02(router).WETH() returns (address weth) { //use router's wnative
            return IERC20(weth);
        } catch { return WNATIVE_DEFAULT; }
    }
    
}