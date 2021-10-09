// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

library LibVaultHealer {
    
    struct Config {
        address withdrawFeeReceiver; //withdrawal fees are sent here
        uint16 withdrawFeeFactor; // determines withdrawal fee
        uint16 controllerFee; //rate paid to user who called earn()
        address rewardFeeReceiver; //"reward" fees on earnings are sent here
        uint16 rewardRate; // "reward" fee rate
        address buybackFeeReceiver; //burn address for CRYSTL
        uint16 buybackRate; // crystl burn rate
    }
    
    uint256 constant FEE_MAX_TOTAL = 10000; //hard-coded maximum fee (100%)
    uint256 constant FEE_MAX = 10000; // 100 = 1% : basis points
    uint256 constant WITHDRAW_FEE_FACTOR_MAX = 10000; //means 0% withdraw fee minimum
    uint256 constant WITHDRAW_FEE_FACTOR_LL = 9900; // means 1% withdraw fee maximum
    
    function checkConfig(Config calldata _config) external pure {
        
        require(_config.rewardFeeReceiver != address(0), "Invalid reward address");
        require(_config.buybackFeeReceiver != address(0), "Invalid buyback address");
        require(_config.controllerFee + _config.rewardRate + _config.buybackRate <= FEE_MAX_TOTAL, "Max fee of 100%");
        require(_config.withdrawFeeFactor >= WITHDRAW_FEE_FACTOR_LL, "_withdrawFeeFactor too low");
        require(_config.withdrawFeeFactor <= WITHDRAW_FEE_FACTOR_MAX, "_withdrawFeeFactor too high");
    }
    
}