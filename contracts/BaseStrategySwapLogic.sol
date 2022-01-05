 // SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./BaseStrategy.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./libs/VaultSettings.sol";
import "./libs/HardMath.sol";
import "./libs/LibVaultSwaps.sol";
import "hardhat/console.sol";

//Contains the strategy's functions related to swapping, earning, etc.
abstract contract BaseStrategySwapLogic is BaseStrategy {
    using SafeERC20 for IERC20;

    function earn() external onlyVaultHealer virtual returns (bool success, uint wantLocked) {
        IERC20 wantToken = config.wantToken;
        uint wantBalanceBefore = wantToken.balanceOf(address(this)); //Don't touch starting want balance (anti-rug)
        _vaultHarvest(); // Harvest farm tokens

        uint dust = settings.dust; //minimum number of tokens to bother trying to compound
        
        uint len = config.earned.length;
        for (uint i; i < len; i++) { //Process each earned token
            IERC20 earnedToken = config.earned[i];
            if (address(earnedToken) == address(0)) break;

            uint256 earnedAmt = earnedToken.balanceOf(address(this));
            if (earnedToken == wantToken)
                earnedAmt -= wantBalanceBefore; //ignore pre-existing want tokens
                
            if (earnedAmt > dust) {
                success = true; //We have something worth compounding
                LibVaultSwaps.safeSwapToETH(settings, earnedAmt, earnedToken, msg.sender); //msg.sender == VH
            }
        }
        return (success, wantLockedTotal());
    }

    //Converts native eth to want tokens
    function compound() external payable onlyVaultHealer returns (uint256 wantAdded) {
        IERC20 wantToken = config.wantToken;
        uint wantBalanceBefore = wantToken.balanceOf(address(this));
        uint vaultSharesBefore = vaultSharesTotal();
        uint wantLockedBefore = wantBalanceBefore + vaultSharesBefore;

        IERC20 token0 = config.lpToken[0];
        IERC20 token1 = config.lpToken[1];
        uint nativeAmount = address(this).balance;
        if (address(token0) == address(0)) { //single stake
            LibVaultSwaps.safeSwapFromETH(settings, nativeAmount, token0, address(this));
        } else {
            LibVaultSwaps.safeSwapFromETH(settings, nativeAmount / 2, token0, address(this));
            LibVaultSwaps.safeSwapFromETH(settings, nativeAmount / 2, token1, address(this));
            LibVaultSwaps.optimalMint(IUniPair(address(wantToken)), token0, token1); // Get want tokens, ie. add liquidity
        }
        uint wantLockedAfter = _farm(wantToken.balanceOf(address(this)), vaultSharesBefore);

        return wantLockedAfter - wantLockedBefore;
    }
    
    //Safely deposits want tokens in farm
    function _farm() internal override returns (uint wantLockedAfter) {
            return _farm(config.wantToken.balanceOf(address(this)), vaultSharesTotal());
    }

    //Safely deposits want tokens in farm
    function _farm(uint _wantBalance, uint _vaultSharesBefore) internal returns (uint wantLockedAfter) {
        if (_wantBalance == 0) return _vaultSharesBefore;
        
        _vaultDeposit(_wantBalance); //approves the transfer then calls the pool contract to deposit

        wantLockedAfter = wantLockedTotal();

        //including settings.dust to reduce the chance of false positives
        //safety check, will fail if there's a deposit fee rugpull or serious bug taking deposits
        require((wantLockedAfter + settings.dust) * 10000 >= settings.slippageFactorFarm * (_vaultSharesBefore + _wantBalance),
            "High vault deposit slippage");
    }

   receive() external payable {
        require(Address.isContract(msg.sender));
    }
}