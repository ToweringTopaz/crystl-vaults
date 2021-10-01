// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./libs/PrismLibrary2.sol";

import "./BaseStrategyConfig.sol";
import "./PathStorage.sol";

//Generic swap logic, etc.
abstract contract BaseStrategySwapLogic is BaseStrategyConfig, PathStorage {
    using SafeERC20 for IERC20;
    
    address immutable public wantAddress;
    
    uint256 immutable earnedLength; //number of earned tokens;
    uint256 immutable lpTokenLength; //number of underlying tokens (for a LP strategy, usually 2);
    
    address public router;
    
    address[8] public earned;
    address[8] public lpToken;
    
    uint256 public burnedAmount; //Total CRYSTL burned by this vault

    constructor(
        address _wantAddress,
        Settings memory _settings,
        address[8] memory _earned,
        address[8] memory _lpToken,
        address[][] memory _paths
    ) BaseStrategyConfig(_settings) {
        wantAddress = _wantAddress;
        
        uint i;
        for (i = 0; i < _paths.length; i++) {
            _setPath(_paths[i]); //copies paths to storage
        }
        
        //The number of earned tokens should not be expected to change
        for (i = 0; i < _earned.length && _earned[i] != address(0); i++) {
            earned[i] = _earned[i];
        }
        earnedLength = i;
        
        //If no LP tokens, try to look them up from the LP token ABI. If not, want must be a single-stake
        if (_lpToken[0] == address(0)) {
            require(_lpToken[1] == address(0), "bad lpToken array");
            
            try IUniPair(_wantAddress).token0() returns (address _token0) {
                lpToken[0] = _token0;
                lpToken[1] = IUniPair(_wantAddress).token1();
            } catch { //if not LP, then single stake
                lpToken[0] = _wantAddress;
            }
        }
        
        //The number of LP tokens should not be expected to change
        for (i = 0; i < lpToken.length && lpToken[i] != address(0); i++) {
            lpToken[i] = _lpToken[i];
        }
        lpTokenLength = i;
    }
    
    //simple balance functions
    function wantBalance() internal view returns (uint256) {
        return IERC20(wantAddress).balanceOf(address(this));
    }
    
    function wantLockedTotal() public view returns (uint256) {
        return wantBalance() + vaultSharesTotal();
    }
    
    //number of tokens currently deposited in the pool
    function vaultSharesTotal() public virtual view returns (uint256);
    //to deposit tokens in the pool
    function _vaultDeposit(uint256 _amount) internal virtual;
    
    //Adds or modifies a swap path
    function setPath(address[] calldata _path) external onlyOwner {
        _setPath(_path);
    }

    function _swapEarnedToLP(address _to, uint256 _wantBal) external returns (bool success) {
        require(msg.sender == address(this)); //external call by this contract only

        for (uint i; i < earnedLength; i++ ) { //Process each earned token, whether it's 1, 2, or 8.
            address earnedAddress = earned[i];
            console.log("_swapEarnedToLP: earnedAddress is %s", earnedAddress);
            
            uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));
            if (earnedAddress == wantAddress) earnedAmt -= _wantBal; //ignore pre-existing want tokens
            
            uint dust = settings.dust; //minimum number of tokens to bother trying to compound
            console.log("_swapEarnedToLP: earnedAmt is %s; greater than dust? %s", earnedAmt, earnedAmt > dust);
    
            if (earnedAmt > dust) {
                success = true; //We have something worth compounding
                
                earnedAmt = distributeFees(earnedAddress, earnedAmt, _to); // handles all fees for this earned token
        
                console.log("_swapEarnedToLP: earnedAmt after fees is %s", earnedAmt);
                console.log("_swapEarnedToLP: lpTokenLength is %s", lpTokenLength);
                
                // Swap half earned to token0, half to token1 (or split evenly however we must, for balancer etc)
                // Same logic works if lpTokenLength == 1 ie single-staking pools
                for (uint j; j < lpTokenLength; i++) {
                    _safeSwap(earnedAmt / lpTokenLength, earnedAddress, lpToken[j], address(this));
                }
            }
        }
        //lpTokenLength == 1 means single-stake, not LP
        if (success && lpTokenLength > 1) {
            // Get want tokens, ie. add liquidity
            PrismLibrary2.optimalMint(wantAddress, lpToken[0], lpToken[1]);
        }
    }
    function _safeSwap(
        uint256 _amountIn,
        address _tokenA,
        address _tokenB,
        address _to
    ) internal {
        //Handle one-token paths which are simply a transfer
        if (_tokenA == _tokenB) {
            //swapping same token to self? do nothing
            if (_to == address(this))
                return;
            //burning crystl?
            if (_tokenA == CRYSTL && _to == settings.buybackFeeReceiver)
                burnedAmount += _amountIn;
            IERC20(_tokenA).safeTransfer(_to, _amountIn);
            return;
        }
        address[] memory path = getPath(_tokenA, _tokenB);
        
        uint256[] memory amounts = settings.router.getAmountsOut(_amountIn, path);
        uint256 amountOut = amounts[amounts.length - 1];

        if (_tokenB == CRYSTL && _to == settings.buybackFeeReceiver) {
            burnedAmount += amountOut;
        }
        amountOut = amountOut * settings.slippageFactor / 10000;
        
        IERC20(_tokenA).safeIncreaseAllowance(address(router), _amountIn);
        if (settings.feeOnTransfer) {
            settings.router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                _amountIn,
                amountOut,
                path,
                _to,
                block.timestamp + 600
            );
        } else {
            IUniRouter02(router).swapExactTokensForTokens(
                _amountIn,
                amountOut,
                path,
                _to,
                block.timestamp + 600
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
        if (settings.buybackRate > 0) {
            uint256 buyBackAmt = _earnedAmt * buybackRate / FEE_MAX;
            _safeSwap(buyBackAmt, _earnedAddress, CRYSTL, settings.buybackFeeReceiver);
            earnedAmt -= buyBackAmt;
        }
        
        return earnedAmt;
    }
    
    function collectWithdrawFee(uint256 _wantAmt) internal returns (uint256) {
        uint256 withdrawFee = Math.ceilDiv(
            _wantAmt * (WITHDRAW_FEE_FACTOR_MAX - settings.withdrawFeeFactor),
            WITHDRAW_FEE_FACTOR_MAX
        );
        if (withdrawFee == 0) IERC20(wantAddress).safeTransfer(settings.withdrawFeeReceiver, withdrawFee);
        return _wantAmt - withdrawFee;
    }
    
    //Safely deposits want tokens in farm
    function _farm() internal override {
        uint256 wantAmt = wantBalance();
        if (wantAmt == 0) return;
        
        uint256 sharesBefore = vaultSharesTotal();
        
        _vaultDeposit(wantAmt); //approves transfer then calls the pool contract to deposit
        uint256 sharesAfter = vaultSharesTotal();
        
        require(sharesAfter + wantBalance() >= sharesBefore + wantAmt * settings.slippageFactor / 10000,
            "High vault deposit slippage"); //safety check, will fail if there's a deposit fee rugpull
        return;
    }
}