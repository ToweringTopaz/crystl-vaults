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

    function earn(VaultSettings calldata settings) external onlyVaultHealer virtual returns (bool success, uint wantLocked) {
        uint wantBalanceBefore = wantToken.balanceOf(address(this)); //Don't touch starting want balance (anti-rug)
        _vaultHarvest(); // Harvest farm tokens

        uint dust = settings.dust; //minimum number of tokens to bother trying to compound
        
        for (uint i; i < earned.length && address(earned[i]) != address(0); i++) { //Process each earned token
            IERC20 earnedToken = earned[i];
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

    //The proceeds from depositAmt are treated much the same as direct want token deposits. The remainder represents autocompounded earnings 
    //which don't generate new shares of any kind
    function compound(VaultSettings calldata settings, uint256 depositAmt, uint256 _exportSharesTotal, uint256 _sharesTotal) external payable onlyVaultHealer returns (uint256 sharesAdded) {
        assert(msg.value >= depositAmt);
        uint wantBalanceBefore = wantToken.balanceOf(address(this));
        uint vaultSharesBefore = vaultSharesTotal();
        uint wantLockedBefore = wantBalanceBefore + vaultSharesBefore;
        assert(_sharesTotal == 0 || wantLockedBefore > _exportSharesTotal); //If there are compounding shares, exportSharesTotal can't be the entirety of the token amount

        if (address(lpToken[1]) == address(0)) { //single stake
            LibVaultSwaps.safeSwapFromETH(settings, msg.value, lpToken[0], address(this));
        } else {
            LibVaultSwaps.safeSwapFromETH(settings, msg.value / 2, lpToken[0], address(this));
            LibVaultSwaps.safeSwapFromETH(settings, msg.value / 2, lpToken[1], address(this));
            LibVaultSwaps.optimalMint(IUniPair(address(wantToken)), lpToken[0], lpToken[1]); // Get want tokens, ie. add liquidity
        }
        uint wantLockedAfter = _farm(wantToken.balanceOf(address(this)), vaultSharesBefore, settings.dust, settings.slippageFactor);

        uint wantAdded = wantLockedAfter - wantLockedBefore;
        sharesAdded = wantAdded * depositAmt / msg.value; //portion to be counted as a deposit, minting shares

        if (_sharesTotal > 0) {
            uint compoundingWantBefore = wantLockedBefore - _exportSharesTotal; //auocompounding want tokens only, no maximizer portion
            sharesAdded = HardMath.mulDiv(sharesAdded, _sharesTotal, compoundingWantBefore);
        }
    }
    
    //Safely deposits want tokens in farm
    function _farm(uint96 dust, uint16 slippageFactor) internal returns (uint wantLockedAfter) {
            return _farm(wantToken.balanceOf(address(this)), vaultSharesTotal(), dust, slippageFactor);
    }

    //Safely deposits want tokens in farm
    function _farm(uint _wantBalance, uint _vaultSharesBefore, uint96 dust, uint16 slippageFactor) internal returns (uint wantLockedAfter) {
        if (_wantBalance == 0) return _vaultSharesBefore;
        
        _vaultDeposit(_wantBalance); //approves the transfer then calls the pool contract to deposit

        wantLockedAfter = wantToken.balanceOf(address(this)) + vaultSharesTotal();

        //including settings.dust to reduce the chance of false positives
        //safety check, will fail if there's a deposit fee rugpull or serious bug taking deposits
        require((wantLockedAfter + dust) * 10000 / (_vaultSharesBefore + _wantBalance) >= slippageFactor,
            "High vault deposit slippage");
    }

   receive() external payable {
        //assert(msg.sender == address(settings.router)); // only accept ETH via fallback if it's a router refund
    }
}