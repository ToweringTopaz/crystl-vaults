// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./libs/PrismLibrary2.sol";

import "./BaseStrategy.sol";
import "./PathStorage.sol";

//Contains the strategy's functions related to swapping, earning, etc.
abstract contract BaseStrategySwapLogic is BaseStrategy, PathStorage {
    using SafeERC20 for IERC20;
    
    //max number of supported lp/earned tokens
    uint256 constant LP_LEN = 2;
    uint256 constant EARNED_LEN = 8;
    
    //Token constants used for fees, etc
    address constant DAI = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address constant CRYSTL = 0x76bF0C28e604CC3fE9967c83b3C3F31c213cfE64;
    address constant WNATIVE = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    
    uint256 constant FEE_MAX = 10000; // 100 = 1% : basis points
    
    address immutable public wantAddress; //The token which is deposited and earns a yield 
    uint256 immutable earnedLength; //number of earned tokens;
    uint256 immutable lpTokenLength; //number of underlying tokens (for a LP strategy, usually 2);
    
    address[EARNED_LEN] public earned;
    address[LP_LEN] public lpToken;
    
    uint256 public burnedAmount; //Total CRYSTL burned by this vault
    uint256 public lastEarnBlock = block.number;
    uint256 public lastGainBlock; //last time earn() produced anything

    constructor(
        address _wantAddress,
        address[] memory _earned,
        address[][] memory _paths
    ) {
        
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
    function _transferWant(address _to, uint256 _amount) internal override {
        IERC20(wantAddress).safeTransfer(_to, _amount);   
    }
    //approves the want token for transfer out
    function _approveWant(address _to, uint256 _amount) internal override {
        IERC20(wantAddress).safeIncreaseAllowance(_to, _amount);   
    }
    
    //returns without action if earn is not ready
    modifier whenEarnIsReady virtual {
        if (block.number >= lastEarnBlock + settings.minBlocksBetweenEarns && !paused()) {
            _;
        }
    }
    
    //external call by this contract only
    modifier onlyThisContract {
        require(msg.sender == address(this));
        _;
    }
    
    //Adds or modifies a swap path
    function setPath(address[] calldata _path) external onlyGov {
        _setPath(_path);
    }

    function _earn(address _to) internal whenEarnIsReady {
        
        //Starting want balance which is not to be touched (anti-rug)
        uint wantBalanceBefore = _wantBalance();
        
        // Harvest farm tokens
        _vaultHarvest();
    
        // Converts farm tokens into want tokens
        //Try/catch means we carry on even if compounding fails for some reason
        try this._swapEarnedToWant(_to, wantBalanceBefore) returns (bool success) {
            if (success) {
                lastGainBlock = block.number; //So frontend can see if a vault no longer actually gains any value
                _farm(); //deposit the want tokens so they can begin earning
            }
        } catch {}
        
        lastEarnBlock = block.number;
    }

    //Called externally by this contract so that if it fails, the error is caught rather than blocking
    function _swapEarnedToWant(address _to, uint256 _wantBal) external onlyThisContract returns (bool success) {

        for (uint i; i < earnedLength; i++ ) { //Process each earned token, whether it's 1, 2, or 8.
            address earnedAddress = earned[i];
            
            uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));
            if (earnedAddress == wantAddress) earnedAmt -= _wantBal; //ignore pre-existing want tokens
            
            uint dust = settings.dust; //minimum number of tokens to bother trying to compound
    
            if (earnedAmt > dust) {
                success = true; //We have something worth compounding
                earnedAmt = distributeFees(earnedAddress, earnedAmt, _to); // handles all fees for this earned token
                
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
    
    //Checks whether a swap is burning crystl, and if so, tracks it
    modifier updateBurn(address _token, address _to) {
        if (_token == CRYSTL && _to == settings.buybackFeeReceiver) {
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
            //swapping same token to self? do nothing
            if (_to == address(this))
                return;
            IERC20(_tokenA).safeTransfer(_to, _amountIn);
            return;
        }
        address[] memory path = findPath(_tokenA, _tokenB);
        
        uint256[] memory amounts = settings.router.getAmountsOut(_amountIn, path);
        uint256 amountOut = amounts[amounts.length - 1] * settings.slippageFactor / 10000;
        
        IERC20(_tokenA).safeIncreaseAllowance(address(settings.router), _amountIn);
        if (settings.feeOnTransfer) {
            settings.router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                _amountIn,
                amountOut,
                path,
                _to,
                block.timestamp + 600
            );
        } else {
            settings.router.swapExactTokensForTokens(
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
        if (buybackRate > 0) {
            uint256 buyBackAmt = _earnedAmt * buybackRate / FEE_MAX;
            _safeSwap(buyBackAmt, _earnedAddress, CRYSTL, settings.buybackFeeReceiver);
            earnedAmt -= buyBackAmt;
        }
        
        return earnedAmt;
    }
    
    //Safely deposits want tokens in farm
    function _farm() override internal {
        uint256 wantAmt = _wantBalance();
        if (wantAmt == 0) return;
        
        uint256 sharesBefore = vaultSharesTotal();
        
        _vaultDeposit(wantAmt); //approves transfer then calls the pool contract to deposit
        uint256 sharesAfter = vaultSharesTotal();
        
        //including settings.dust to reduce the chance of false positives
        require(sharesAfter + _wantBalance() + settings.dust >= sharesBefore + wantAmt * settings.slippageFactor / 10000,
            "High vault deposit slippage"); //safety check, will fail if there's a deposit fee rugpull
        return;
    }
}