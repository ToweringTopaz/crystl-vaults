// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./PausableTL.sol";

import "./libs/IUniRouter.sol";

abstract contract BaseStrategy is PausableTL {

    uint256 constant FEE_MAX_TOTAL = 10000; //hard-coded maximum fee (100%)
    uint256 constant FEE_MAX = 10000; // 100 = 1% : basis points
    
    uint256 constant WITHDRAW_FEE_FACTOR_MAX = 10000; //means 0% withdraw fee minimum
    uint256 constant WITHDRAW_FEE_FACTOR_LL = 9900; // means 1% withdraw fee maximum
    
    uint256 constant SLIPPAGE_FACTOR_UL = 9950; // Must allow for at least 0.5% slippage (rounding errors)
    
    struct Settings {
        IUniRouter02 router; //UniswapV2 compatible router
        
        address withdrawFeeReceiver; //withdrawal fees are sent here
        
        address rewardFeeReceiver; //"reward" fees on earnings are sent here
        address buybackFeeReceiver; //burn address for CRYSTL
        
        uint16 controllerFee; //rate paid to user who called earn()
        uint16 rewardRate; // "reward" fee rate
        uint16 buybackRate; // crystl burn rate
        
        uint256 withdrawFeeFactor; // determines withdrawal fee
        uint256 slippageFactor; // sets a limit on losses due to deposit fee in pool, reflect fees, rounding errors, etc.
        uint256 tolerance; // "Hidden Gem", "Premiere Gem", etc. frontend indicator
        bool feeOnTransfer; // Swap with the router's reflect-token mode
        uint256 dust; //min token amount to swap/deposit. Prevents token waste, exploits and unnecessary reverts
        uint256 minBlocksBetweenEarns; //Prevents token waste, exploits and unnecessary reverts
    }
    
    Settings public settings; //The above data, in storage
    
    uint256 public lastEarnBlock = block.number;
    
    //Some routers such as dfyn use a non-standard WNATIVE token. We can get it from the router
    address constant WNATIVE_DEFAULT = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address internal WNATIVE;
    
    modifier onlyEarner virtual { _; } //overridden to restrict "earn"
    modifier onlyGov virtual; //"gov"
    
    modifier whenEarnIsReady virtual { //returns without action if earn is not ready
        if (block.number >= lastEarnBlock + settings.minBlocksBetweenEarns && !paused()) {
            _;
        }
    }
    modifier onlyThisContract { //external call by this contract only
        require(msg.sender == address(this));
        _;
    }
    
    
    event SetSettings(Settings _settings);
    
    function _vaultDeposit(uint256 _amount) internal virtual;
    function _vaultWithdraw(uint256 _amount) internal virtual;
    function _vaultHarvest() internal virtual;
    function earn(address _to) external virtual;
    
    function sharesTotal() external virtual view returns (uint256);
    function vaultSharesTotal() public virtual view returns (uint256);
    function _wantBalance() internal virtual view returns (uint256);

    function wantLockedTotal() public view returns (uint256) {
        return _wantBalance() + vaultSharesTotal();
    }

    function _approveWant(address _to, uint256 _amount) internal virtual;
    
    function _emergencyVaultWithdraw() internal virtual;
    function _farm() internal virtual;
    
    constructor(Settings memory _settings) {
        _setSettings(_settings); //copies settings to storage
    }
    
    //for front-end
    function buyBackRate() external view returns (uint) { 
        return settings.buybackRate;
    }
    function tolerance() external view returns (uint) {
        return settings.tolerance;
    }
    
    //called by gov's setSettings and by the constructor
    function _setSettings(Settings memory _settings) private {
        require(_settings.rewardFeeReceiver != address(0), "Invalid reward address");
        require(_settings.buybackFeeReceiver != address(0), "Invalid buyback address");
        require(_settings.controllerFee + _settings.rewardRate + _settings.buybackRate <= FEE_MAX_TOTAL, "Max fee of 100%");
        require(_settings.withdrawFeeFactor >= WITHDRAW_FEE_FACTOR_LL, "_withdrawFeeFactor too low");
        require(_settings.withdrawFeeFactor <= WITHDRAW_FEE_FACTOR_MAX, "_withdrawFeeFactor too high");
        require(_settings.slippageFactor <= SLIPPAGE_FACTOR_UL, "_slippageFactor too high");
        try _settings.router.factory() returns (address) {}
        catch { revert("Invalid router"); }
        try _settings.router.WETH() returns (address weth) { //use router's wnative
            WNATIVE = weth;
        } catch { WNATIVE = WNATIVE_DEFAULT; }
        
        settings = _settings;
        
        emit SetSettings(_settings);
    }
    
    function setSettings(Settings calldata _settings) external onlyGov {
        _setSettings(_settings);
    }
    
    function pause() external onlyGov {
        _pause();
    }
    function unpause() external onlyGov {
        _unpause();
    }
    function panic() external onlyGov {
        _pause();
        _emergencyVaultWithdraw();
    }
    function unpanic() external onlyGov {
        _unpause();
        _farm();
    }
}