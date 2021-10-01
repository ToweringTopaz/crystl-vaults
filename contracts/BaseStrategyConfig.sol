// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./libs/IUniRouter.sol";

import "./PausableTL.sol";

import "hardhat/console.sol";

//Handles basic configuration for a strategy. Constants, settings, and admin functions are here.
abstract contract BaseStrategyConfig is PausableTL, Ownable {
    
    struct Settings {
        address rewardFeeReceiver;
        address withdrawFeeReceiver;
        address buybackFeeReceiver;
        IUniRouter02 router;
        uint16 controllerFee;
        uint16 rewardRate;
        uint16 buybackRate;
        uint256 withdrawFeeFactor;
        uint256 slippageFactor;
        uint256 tolerance;
        bool feeOnTransfer;
        uint256 dust; //minimum raw token value considered to be worth swapping or depositing
        uint256 minBlocksBetweenEarns;
    }
    
    address constant DAI = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address constant CRYSTL = 0x76bF0C28e604CC3fE9967c83b3C3F31c213cfE64;
    address constant WNATIVE = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    uint256 constant FEE_MAX_TOTAL = 10000;
    uint256 constant FEE_MAX = 10000; // 100 = 1%
    uint256 constant WITHDRAW_FEE_FACTOR_MAX = 10000;
    uint256 constant WITHDRAW_FEE_FACTOR_LL = 9900;
    uint256 constant SLIPPAGE_FACTOR_UL = 9950;

    //max number of lp/earned tokens
    uint256 constant LP_LEN = 2;
    uint256 constant EARNED_LEN = 2;

    event SetSettings(Settings _settings);
    
    Settings public settings;
    
    constructor(Settings memory _settings) {
        _setSettings(_settings); //copies settings to storage
    }
    
    function _farm() internal virtual;
    function _emergencyVaultWithdraw() internal virtual;
    
    function pause() external onlyOwner {
        _pause();
    }
    function unpause() external onlyOwner {
        _unpause();
    }
    function panic() external onlyOwner {
        _pause();
        _emergencyVaultWithdraw();
    }
    function unpanic() external onlyOwner {
        _unpause();
        _farm();
    }
    function setSettings(Settings calldata _settings) external onlyOwner {
        _setSettings(_settings);
    }

    //private configuration functions
    function _setSettings(Settings memory _settings) private {
        require(_settings.rewardFeeReceiver != address(0), "Invalid reward address");
        require(_settings.withdrawFeeReceiver != address(0), "Invalid Withdraw address");
        require(_settings.buybackFeeReceiver != address(0), "Invalid buyback address");
        require(_settings.controllerFee + _settings.rewardRate + _settings.buybackRate <= FEE_MAX_TOTAL, "Max fee of 100%");
        require(_settings.withdrawFeeFactor >= WITHDRAW_FEE_FACTOR_LL, "_withdrawFeeFactor too low");
        require(_settings.withdrawFeeFactor <= WITHDRAW_FEE_FACTOR_MAX, "_withdrawFeeFactor too high");
        require(_settings.slippageFactor <= SLIPPAGE_FACTOR_UL, "_slippageFactor too high");
        try _settings.router.factory() returns (address) {}
        catch { revert("Invalid router"); }
        
        settings = _settings;
        
        emit SetSettings(_settings);
    }
    
    //for front-end
    function buyBackRate() external view returns (uint) { return settings.buybackRate; }
    function tolerance() external view returns (uint) { return settings.tolerance; }
}