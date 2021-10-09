// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./IUniRouter.sol";
import "../BaseStrategy.sol";
import "../Magnetite.sol";
import "./LibVaultHealer.sol";

//Functions specific to the strategy code
library LibBaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    
    struct Settings {
        IUniRouter02 router; //UniswapV2 compatible router
        uint16 slippageFactor; // sets a limit on losses due to deposit fee in pool, reflect fees, rounding errors, etc.
        uint16 tolerance; // "Hidden Gem", "Premiere Gem", etc. frontend indicator
        uint64 minBlocksBetweenEarns; //Prevents token waste, exploits and unnecessary reverts
        
        address wnative; //configured wmatic/weth/etc address, based on router/defaults
        uint88 dust; //min token amount to swap/deposit. Prevents token waste, exploits and unnecessary reverts
        bool feeOnTransfer;
        
        Magnetite magnetite;
        
        address withdrawFeeReceiver; //withdrawal fees are sent here
        uint16 withdrawFeeFactor; // determines withdrawal fee
        uint16 controllerFee; //rate paid to user who called earn()
        address rewardFeeReceiver; //"reward" fees on earnings are sent here
        uint16 rewardRate; // "reward" fee rate
        address buybackFeeReceiver; //burn address for CRYSTL
        uint16 buybackRate; // crystl burn rate
        
    }
    
    struct SettingsInput {
        address masterchefaddress;
        address tactic;
        uint256 pid;
        address vaultHealerAddress;
        address wantAddress;
        address router; //UniswapV2 compatible router
        
        uint16 slippageFactor; // sets a limit on losses due to deposit fee in pool, reflect fees, rounding errors, etc.
        uint16 tolerance; // "Hidden Gem", "Premiere Gem", etc. frontend indicator
        uint64 minBlocksBetweenEarns; //Prevents token waste, exploits and unnecessary reverts
        
        bool feeOnTransfer;
        uint88 dust; //min token amount to swap/deposit. Prevents token waste, exploits and unnecessary reverts        
    }
    
    //For tracking earned/burned
    struct VaultStats {
        uint128 totalEarned;
        uint128 totalBurned;
    }
    

    uint256 constant SLIPPAGE_FACTOR_UL = 9950; // Must allow for at least 0.5% slippage (rounding errors)
    

        //Token constants used for fees, etc    
    address constant DAI = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address constant CRYSTL = 0x76bF0C28e604CC3fE9967c83b3C3F31c213cfE64;
    address constant WNATIVE_DEFAULT = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    
    uint256 constant FEE_MAX = 10000; // 100 = 1% : basis points
    
    event SetSettings(Settings _settings);

    function setSettings(Settings storage settings, SettingsInput memory _settings) external {
        try IUniRouter02(_settings.router).factory() returns (address) 
        {settings.router = IUniRouter02(_settings.router);}
        catch { revert("Invalid router"); }
        
        require(_settings.slippageFactor <= SLIPPAGE_FACTOR_UL, "_slippageFactor too high");
        settings.slippageFactor = _settings.slippageFactor;
        
        settings.tolerance = _settings.tolerance;
        settings.minBlocksBetweenEarns = _settings.minBlocksBetweenEarns;
        
        try IUniRouter02(_settings.router).WETH() returns (address weth) { //use router's wnative
            settings.wnative = weth;
        } catch { settings.wnative = WNATIVE_DEFAULT; }
        
        settings.feeOnTransfer = _settings.feeOnTransfer;
        
        settings.dust = _settings.dust;
        
        emit SetSettings(settings);
    }
    function _updateConfig(Settings storage settings, LibVaultHealer.Config calldata _config) external {
        LibVaultHealer.checkConfig(_config);
        settings.withdrawFeeReceiver = _config.withdrawFeeReceiver;
        settings.withdrawFeeFactor = _config.withdrawFeeFactor;
        settings.controllerFee = _config.controllerFee;
        settings.rewardFeeReceiver = _config.rewardFeeReceiver;
        settings.rewardRate = _config.rewardRate;
        settings.buybackFeeReceiver = _config.buybackFeeReceiver;
        settings.buybackRate = _config.buybackRate;
        
        emit SetSettings(settings);
    }
    
    function distributeFees(Settings storage settings, VaultStats storage stats, address _earnedAddress, uint256 _earnedAmt, address _to) external returns (uint earnedAmt) {
        uint burnedBefore = IERC20(CRYSTL).balanceOf(settings.buybackFeeReceiver);

        earnedAmt = _earnedAmt;
        // To pay for earn function
        uint256 fee = _earnedAmt * settings.controllerFee / FEE_MAX;
        _safeSwap(settings, fee, _earnedAddress, settings.wnative, _to);
        earnedAmt -= fee; 
        //distribute rewards
        fee = _earnedAmt * settings.rewardRate / FEE_MAX;
        _safeSwap(settings, fee, _earnedAddress, _earnedAddress == CRYSTL ? CRYSTL : DAI, settings.rewardFeeReceiver);
        earnedAmt -= fee;
        //burn crystl
        fee = _earnedAmt * settings.buybackRate / FEE_MAX;
        _safeSwap(settings, fee, _earnedAddress, CRYSTL, settings.buybackFeeReceiver);
        earnedAmt -= fee;

        unchecked { //overflow ok albeit unlikely
            stats.totalEarned += uint128(earnedAmt);
            stats.totalBurned += uint128(IERC20(CRYSTL).balanceOf(settings.buybackFeeReceiver) - burnedBefore);
        }
    }

    function _safeSwap(
        Settings storage settings,
        uint256 _amountIn,
        address _tokenA,
        address _tokenB,
        address _to
    ) public {
        
        //Handle one-token paths which are simply a transfer
        if (_tokenA == _tokenB) {
            if (_to != address(this)) //skip transfers to self
                IERC20(_tokenA).safeTransfer(_to, _amountIn);
            return;
        }
        address[] memory path = settings.magnetite.findAndSavePath(address(settings.router), _tokenA, _tokenB);
        
        uint256[] memory amounts = settings.router.getAmountsOut(_amountIn, path);
        uint256 amountOut = amounts[amounts.length - 1] * settings.slippageFactor / 10000;
        
        //allow router to pull the correct amount in
        IERC20(_tokenA).safeIncreaseAllowance(address(settings.router), _amountIn);
        
        if (_tokenB != settings.wnative || _to.isContract() ) {
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
    
}