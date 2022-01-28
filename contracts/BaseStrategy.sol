// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;


import "./libs/HardMath.sol";
import "./libs/LibQuartz.sol";
import "./libs/Vault.sol";
import "./libs/PrismLibrary.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
//import "@openzeppelin/contracts/utils/Address.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";
import "./libs/IVaultHealer.sol";
import "./libs/IStrategy.sol";
import "./libs/Tactics.sol";
import "./libs/Vault.sol";
import "./FirewallProxyImplementation.sol";

abstract contract BaseStrategy is FirewallProxyImplementation, IStrategy {
    using SafeERC20 for IERC20;



    uint constant FEE_MAX = 10000;
    
    struct Settings {
        Tactics.TacticsA tacticsA;
        Tactics.TacticsB tacticsB;
        IERC20 wantToken; //The token which is deposited and earns a yield
        uint256 slippageFactor; //(16) sets a limit on losses due to deposit fee in pool, reflect fees, rounding errors, etc.
        uint256 feeOnTransfer; //(8) 0 = false; 1 = true
        uint256 dust; //(96) min token amount to swap/deposit. Prevents token waste, exploits and unnecessary reverts
        uint256 targetVid; //(32)
        IUniRouter router; //UniswapV2 compatible router
        IMagnetite magnetite;
        IERC20[2] lpToken;
        IERC20[4] earned;
    }

    function vaultSharesTotal() external view returns (uint256) {
        return _vaultSharesTotal(getSettings());
    }
    function _vaultSharesTotal(Settings memory s) internal view returns (uint256) {
        return Tactics.vaultSharesTotal(s.tacticsA);
    }
    function _vaultDeposit(Settings memory s, uint256 _amount) internal {   
        //token allowance for the pool to pull the correct amount of funds only
        s.wantToken.safeIncreaseAllowance(address(uint160(Tactics.TacticsA.unwrap(s.tacticsA) >> 96)), _amount); //address(s.tacticsA >> 96) is masterchef        
        Tactics.deposit(s.tacticsA, s.tacticsB, _amount);
    }
    function _farm(Settings memory s) internal virtual;
    
    function wantLockedTotal() external virtual view returns (uint256) {
        Settings memory s = getSettings();
        return s.wantToken.balanceOf(address(this)) + _vaultSharesTotal(s);
    }

    function panic() external {
        Settings memory s = getSettings();
        Tactics.emergencyVaultWithdraw(s.tacticsA, s.tacticsB);
    }
    function unpanic() external { 
        Settings memory s = getSettings();
        _farm(s);
    }
    function router() external view returns (IUniRouter) {
        Settings memory s = getSettings();
        return s.router;
    }
    function wantToken() external view returns (IERC20) {
        Settings memory s = getSettings();
        return s.wantToken;
    }
    function targetVid() external view returns (uint256) {
        Settings memory s = getSettings();
        return s.targetVid;
    }

    function getSettings() public view returns (Settings memory settings) {
        bytes memory data = getProxyData();
        assembly {
            settings := data
        }
    }

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

    //VaultHealer calls this to add funds at a user's direction. VaultHealer manages the user shares
    function deposit(uint256 _wantAmt, uint256 _sharesTotal) external returns (uint256 sharesAdded) {
        Settings memory s = getSettings();
        // _earn(_from); //earn before deposit prevents abuse
        uint wantBal = s.wantToken.balanceOf(address(this)); ///todo: why would there be want sitting in the strat contract?
        uint wantLockedBefore = wantBal + _vaultSharesTotal(s); //todo: why is this different to deposit function????????????
        uint dust = s.dust;

        if (_wantAmt < dust) return 0; //do nothing if nothing is requested

        //Before calling deposit here, the vaulthealer records how much the user deposits. Then with this
        //call, the strategy tells the vaulthealer to proceed with the transfer. This minimizes risk of
        //a rogue strategy 
        IVaultHealer(msg.sender).executePendingDeposit(address(this), uint112(_wantAmt));
        _farm(s); //deposits the tokens in the pool
        // Proper deposit amount for tokens with fees, or vaults with deposit fees
        sharesAdded = s.wantToken.balanceOf(address(this)) + _vaultSharesTotal(s) - wantLockedBefore;
        if (_sharesTotal > 0) { 
            sharesAdded = Math.ceilDiv(sharesAdded * _sharesTotal, wantLockedBefore);
        }
        require(sharesAdded > dust, "deposit: no/dust shares added");
    }

    //Correct logic to withdraw funds, based on share amounts provided by VaultHealer
    function withdraw(uint _wantAmt, uint _userShares, uint _sharesTotal) external returns (uint sharesRemoved, uint wantAmt) {
        Settings memory s = getSettings();
        //User's balance, in want tokens
        uint wantBal = s.wantToken.balanceOf(address(this)); ///todo: why would there be want sitting in the strat contract?
        uint wantLockedBefore = wantBal + _vaultSharesTotal(s); //todo: why is this different to deposit function????????????
        uint256 userWant = _userShares * wantLockedBefore / _sharesTotal;
        
        // user requested all, very nearly all, or more than their balance, so withdraw all
        if (_wantAmt + s.dust > userWant) {
            _wantAmt = userWant;
        }
        
        // Check if strategy has tokens from panic
        if (_wantAmt > wantBal) {
            Tactics.withdraw(s.tacticsA, s.tacticsB, _wantAmt - wantBal);
            
            wantBal = s.wantToken.balanceOf(address(this));
        }

        //Account for reflect, pool withdraw fee, etc; charge these to user
        uint wantLockedAfter = s.wantToken.balanceOf(address(this)) + _vaultSharesTotal(s);
        uint withdrawSlippage = wantLockedAfter < wantLockedBefore ? wantLockedBefore - wantLockedAfter : 0;

        //Calculate shares to remove
        sharesRemoved = Math.ceilDiv(
            (_wantAmt + withdrawSlippage) * _sharesTotal,
            wantLockedBefore
        );

        //Get final withdrawal amount
        if (sharesRemoved > _userShares) {
            sharesRemoved = _userShares;
        }

        _wantAmt = Math.ceilDiv(sharesRemoved * wantLockedBefore, _sharesTotal) - withdrawSlippage;
        if (_wantAmt > wantBal) _wantAmt = wantBal;

        require(_wantAmt > 0, "nothing to withdraw after slippage");
        
        return (sharesRemoved, _wantAmt);
    }
}