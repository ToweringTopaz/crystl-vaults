// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./libs/FullMath.sol";
import "./libs/PrismLibrary2.sol";

import "./BaseStrategy.sol";
import "./Magnetite.sol";

//Contains the strategy's functions related to swapping, earning, etc.
abstract contract BaseStrategySwapLogic is BaseStrategy {
    using SafeERC20 for IERC20;
    
    //max number of supported lp/earned tokens
    uint256 constant LP_LEN = 2;
    uint256 constant EARNED_LEN = 8;
    
    //Token constants used for fees, etc
    address constant DAI = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address constant CRYSTL = 0x76bF0C28e604CC3fE9967c83b3C3F31c213cfE64;
    address constant WNATIVE = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    
    address immutable public wantAddress; //The token which is deposited and earns a yield 
    uint256 immutable earnedLength; //number of earned tokens;
    uint256 immutable lpTokenLength; //number of underlying tokens (for a LP strategy, usually 2);
    
    address[EARNED_LEN] public earned;
    address[LP_LEN] public lpToken;
    
    uint256 public burnedAmount; //Total CRYSTL burned by this vault
    Magnetite private _magnetite; //the contract responsible for pathing

    constructor(
        address _wantAddress,
        address magnetite_,
        address[] memory _earned
    ) {
        
        wantAddress = _wantAddress;
        _magnetite = Magnetite(magnetite_);
        
        uint i;
        //The number of earned tokens should not be expected to change
        for (i = 0; i < _earned.length && _earned[i] != address(0); i++) {
            earned[i] = _earned[i];
        }
        earnedLength = i;
        
        //Look for LP tokens. If not, want must be a single-stake
        uint _lpTokenLength;
        try IUniPair(_wantAddress).token0() returns (address _token0) {
            lpToken[0] = _token0;
            lpToken[1] = IUniPair(_wantAddress).token1();
            _lpTokenLength = 2;
        } catch { //if not LP, then single stake
            lpToken[0] = _wantAddress;
            _lpTokenLength = 1;
        }
        lpTokenLength = _lpTokenLength;
    }
    
    function _wantBalance() internal override view returns (uint256) {
        return IERC20(wantAddress).balanceOf(address(this));
    }
    //transfers the want token
    function _transferWant(address _to, uint256 _amount) internal {
        IERC20(wantAddress).safeTransfer(_to, _amount);   
    }
    //approves the want token for transfer out
    function _approveWant(address _to, uint256 _amount) override internal {
        IERC20(wantAddress).safeIncreaseAllowance(_to, _amount);   
    }
    
    function magnetite() public virtual view returns (Magnetite) {
        return _magnetite;
    }

    function _earn(address _to) internal virtual whenEarnIsReady {
        
        console.log("Getting want balance");
        uint wantBalanceBefore = _wantBalance(); //Don't touch starting want balance (anti-rug)
        
        console.log("Harvesting");
        _vaultHarvest(); // Harvest farm tokens
        console.log("Harvest complete");        
        
        uint dust = settings.dust; //minimum number of tokens to bother trying to compound
        bool success;
        
        for (uint i; i < earnedLength; i++) { //Process each earned token, whether it's 1, 2, or 8.
            address earnedAddress = earned[i];
            console.log("Using earnedAddress %s", earnedAddress);
            uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));
            console.log("earnedAmt is %s", earnedAmt);
            if (earnedAddress == wantAddress)
                earnedAmt -= wantBalanceBefore; //ignore pre-existing want tokens
            console.log("earnedAmt is %s", earnedAmt);
                
            if (earnedAmt > dust) {
                console.log("dust check passed");
                success = true; //We have something worth compounding
                console.log("distributing fees");
                earnedAmt = distributeFees(earnedAddress, earnedAmt, _to); // handles all fees for this earned token
                // Swap half earned to token0, half to token1 (or split evenly however we must, for balancer etc)
                // Same logic works if lpTokenLength == 1 ie single-staking pools
                console.log("lpTokenLength is %s", lpTokenLength);
                for (uint j; j < lpTokenLength; j++) {
                    console.log("swapping %s earned to %s", earnedAmt/lpTokenLength, lpToken[j]);
                    _safeSwap(earnedAmt / lpTokenLength, earnedAddress, lpToken[j], address(this));
                }
            }
        }
        //lpTokenLength == 1 means single-stake, not LP
        if (success) {
            if (lpTokenLength > 1) {
                // Get want tokens, ie. add liquidity
                console.log("calling optimalMint");
                PrismLibrary2.optimalMint(wantAddress, lpToken[0], lpToken[1]);
            }
            console.log("farming");
            _farm();
            console.log("farm complete");
        }
        lastEarnBlock = block.number;
    }
    
    //Checks whether a swap is burning crystl, and if so, tracks it
    modifier updateBurn(address _tokenOut, address _to) {
        address burnAddress = settings.buybackFeeReceiver;
        if (_tokenOut == CRYSTL && _to == settings.buybackFeeReceiver) {
            uint burnedBefore = IERC20(CRYSTL).balanceOf(settings.buybackFeeReceiver);
            _;
            burnedAmount += IERC20(CRYSTL).balanceOf(settings.buybackFeeReceiver) - burnedBefore;
        } else {
            _;
        }
    }
    
    function _safeSwap(
        uint256 _amountIn,
        address _tokenA,
        address _tokenB,
        address _to
    ) internal updateBurn(_tokenB, _to) {
        
        //Handle one-token paths which are simply a transfer
        if (_tokenA == _tokenB) {
            if (_to != address(this)) //skip transfers to self
                IERC20(_tokenA).safeTransfer(_to, _amountIn);
            return;
        }
        address[] memory path = magnetite().findAndSavePath(address(settings.router), _tokenA, _tokenB);
        
        uint256[] memory amounts = settings.router.getAmountsOut(_amountIn, path);
        uint256 amountOut = amounts[amounts.length - 1] * settings.slippageFactor / 10000;
        
        //allow router to pull the correct amount in
        IERC20(_tokenA).safeIncreaseAllowance(address(settings.router), _amountIn);
        
        if (settings.feeOnTransfer) { //reflect mode on
            settings.router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                _amountIn,
                amountOut,
                path,
                _to,
                block.timestamp
            );
        } else { //reflect mode off
            settings.router.swapExactTokensForTokens(
                _amountIn,
                amountOut,
                path,
                _to,
                block.timestamp
            );
        }
    }
    
    function distributeFees(address _earnedAddress, uint256 _earnedAmt, address _to) internal returns (uint earnedAmt) {
        earnedAmt = _earnedAmt;
        
        uint controllerFee = settings.controllerFee;
        uint rewardRate = settings.rewardRate;
        uint buybackRate = settings.buybackRate;
        
        // To pay for earn function
        if (controllerFee > 0) {
            uint256 fee = _earnedAmt * controllerFee / FEE_MAX;
            _safeSwap(fee, _earnedAddress, WNATIVE, _to);
            earnedAmt -= fee;
        }
        //distribute rewards
        if (rewardRate > 0) {
            uint256 fee = _earnedAmt * rewardRate / FEE_MAX;
            if (_earnedAddress == CRYSTL)
                IERC20(_earnedAddress).safeTransfer(settings.rewardFeeReceiver, fee);
            else
                _safeSwap(fee, _earnedAddress, DAI, settings.rewardFeeReceiver);

            earnedAmt -= fee;
        }
        //burn crystl
        if (buybackRate > 0) {
            uint256 buyBackAmt = _earnedAmt * buybackRate / FEE_MAX;
            _safeSwap(buyBackAmt, _earnedAddress, CRYSTL, settings.buybackFeeReceiver);
            earnedAmt -= buyBackAmt;
        }
        
        return earnedAmt;
    }
    
    function collectWithdrawFee(uint _wantAmt) internal returns (uint) {
        uint256 withdrawFee = FullMath.mulDiv(
            _wantAmt,
            WITHDRAW_FEE_FACTOR_MAX - settings.withdrawFeeFactor,
            WITHDRAW_FEE_FACTOR_MAX
        );
        
        //if receiver is 0, strategy keeps fee
        address receiver = settings.withdrawFeeReceiver;
        if (receiver != address(0))
            _transferWant(receiver, withdrawFee);
        return _wantAmt - withdrawFee;
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
}