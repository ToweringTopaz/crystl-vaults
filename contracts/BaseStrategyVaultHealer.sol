// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import"./libs/IVaultHealer.sol";
import "./BaseStrategySwapLogic.sol";

//Deposit and withdraw for a secure VaultHealer-based system. VaultHealer is responsible for tracking user shares.
abstract contract BaseStrategyVaultHealer is BaseStrategySwapLogic {
    using SafeERC20 for IERC20;

    //VaultHealer calls this to add funds at a user's direction. VaultHealer manages the user shares
    function deposit(VaultSettings calldata settings, uint256 _wantAmt, uint256 _wantAmtExport, uint256 _sharesTotal) external onlyVaultHealer returns (uint256 tokensAdded) {
        require (_wantAmtExport <= _wantAmt); //wantAmtExport is the portion of wantAmt that goes to maximizer tokens
        uint96 dust = settings.dust;
        if (_wantAmt < dust) return (0, 0); //do nothing if nothing is requested
        else if (_wantAmt < _wantAmtExport + dust) _wantAmtExport = _wantAmt; //if autocompound portion is dust, fold into maximizer portion
        else if (_wantAmtExport < dust) _wantAmtExport = 0; //if export portion is dust, fold into autocompound

            //todo: why would there be want sitting in the strat contract? - because nothing stops users from transferring in tokens, often flashloaned!
        uint vaultSharesBefore = vaultSharesTotal();
        uint wantBalanceBefore = wantToken.balanceOf(address(this));
        uint wantLockedBefore = vaultSharesBefore + wantBalanceBefore; //todo: why is this different to deposit function???????????? - wantLockedTotal is defined as want balance+ vaultSharesTotal. Sometimes we need the two separately, sometimes we don't

        //Before calling deposit here, the vaulthealer records how much the user deposits. Then with this
        //call, the strategy tells the vaulthealer to proceed with the transfer. This minimizes risk of
        //a rogue strategy 
        vaultHealer.executePendingDeposit(address(this), _wantAmt);

        uint wantLockedAfter = _farm(wantToken.balanceOf(address(this)), vaultSharesBefore, dust, settings.slippageFactorFarm); //deposits the tokens in the pool

        uint tokensAdded = wantLockedTotal() - wantLockedBefore; // Proper deposit amount for tokens with fees, or vaults with deposit fees
        if (tokensAdded > _wantAmt) tokensAdded = _wantAmt; //no credit for excess, improperly added tokens - exploit safety

        exportsAdded = _wantAmtExport * tokensAdded / _wantAmt;   //Final number of maximizer export tokens added
        sharesAdded = tokensAdded - exportsAdded; //compounding shares

        if (_sharesTotal > 0) { //mulDiv prevents overflow for certain tokens/amounts
            sharesAdded = HardMath.mulDiv(sharesAdded, _sharesTotal, (wantLockedBefore - exportSharesTotal));
        }
        require(exportsAdded + sharesAdded > settings.dust, "deposit: no/dust shares added");
    }
    error WithdrawSlippagePanicError(uint vaultWithdrawAmt, uint vaultSharesBefore, uint wantBalanceBefore, uint vaultSharesAfter, uint wantBal, uint16 slippageFactor);    

    //Correct logic to withdraw funds, based on share amounts provided by VaultHealer
    function withdraw(VaultWithdrawData calldata data) external onlyVaultHealer returns (uint sharesRemoved, uint exportsRemoved, uint wantAmt) {
        //User's balance, in want tokens
        uint wantBal = wantToken.balanceOf(address(this));
        uint wantBalanceBefore = wantBal;
        uint vaultSharesBefore = vaultSharesTotal();
        uint wantLockedBefore = vaultSharesBefore + wantBalanceBefore;

        //userWant is the number of want tokens owned by the user, including both export and compounding
        uint userShares = data.userShares;
        uint userExports = data.userExports;
        uint sharesTotal = data.sharesTotal;
        uint256 userWant = userShares > 0 ? HardMath.mulDiv(userShares, wantLockedBefore, sharesTotal) + userExports : userExports;

        wantAmt = data.wantAmt;
        uint wantAmtExport = data.wantAmtExport;
        uint dust = data.dust;

        if (wantAmt + dust > userWant) { // user requested all, very nearly all, or more than their balance, so withdraw all
            wantAmt = userWant;
            wantAmtExport = userExports;
        } else if (userExports < wantAmtExport + dust || wantAmt < wantAmtExport + dust) { 
            wantAmtExport = userExports < wantAmt ? userExports : wantAmt;
        }

        //amount we need to withdraw from the pool. Don't try if we're in a panic
        uint vaultWithdrawAmt = (data.status != VaultStatus.PANIC) && (wantAmt > wantBalanceBefore)
            ? wantAmt - wantBalanceBefore
            : 0;

        if (vaultWithdrawAmt > 0) {
            _vaultWithdraw(wantAmt - wantBalanceBefore);
            wantBal = wantToken.balanceOf(address(this));

            //Account for reflect, pool withdraw fee, etc; charge these to user
            uint vaultSharesAfter = vaultSharesTotal();
            uint wantLockedAfter = wantBal + vaultSharesAfter;
            uint slippageAmt = wantLockedAfter < wantLockedBefore ? wantLockedBefore - wantLockedAfter : 0;

            //if slippage is too high, the vault should autopanic
            unchecked{
                uint slippageFactor = data.slippageFactor;
                if (int(vaultWithdrawAmt - slippageAmt) * 10000 < slippageFactor * vaultWithdrawAmt) {
                    //todo: VH try/catch
                    revert WithdrawSlippagePanicError(vaultWithdrawAmt, vaultSharesBefore, wantBalanceBefore, vaultSharesAfter, wantBal, slippageFactor);
                }
            }

            userWant -= slippageAmt;
        }
        
        userWant = userWant > wantBal

        if (wantAmt + dust > userWant) { // user requested all, very nearly all, or more than their balance, so withdraw all
            wantAmt = userWant;
            wantAmtExport = userExports;
        } else if (userExports < wantAmtExport + dust || wantAmt < wantAmtExport + dust) { 
            wantAmtExport = userExports < wantAmt ? userExports : wantAmt;
        }


        //Calculate shares to remove



        sharesRemoved = HardMath.mulDivRoundingUp(
            wantAmt + slippageAmt - exportsRemoved,
            sharesTotal,
            wantLockedBefore
        );
        
        //Get final withdrawal amount
        if (sharesRemoved > userShares) {
            sharesRemoved = userShares;
            wantAmt = HardMath.mulDiv(sharesRemoved, wantLockedBefore, sharesTotal) - slippageAmt;
        }
        if (wantAmt > wantBal) wantAmt = wantBal;
        require(wantAmt > 0, "nothing to withdraw after slippage");
        
        wantToken.safeIncreaseAllowance(address(vaultHealer), wantAmt);
        return (sharesRemoved, exportsRemoved, wantAmt);
    }

}