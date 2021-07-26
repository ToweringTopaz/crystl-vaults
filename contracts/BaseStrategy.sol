// SPDX-License-Identifier: MIT

/*
Join us at PolyCrystal.Finance!
█▀▀█ █▀▀█ █░░ █░░█ █▀▀ █▀▀█ █░░█ █▀▀ ▀▀█▀▀ █▀▀█ █░░ 
█░░█ █░░█ █░░ █▄▄█ █░░ █▄▄▀ █▄▄█ ▀▀█ ░░█░░ █▄▄█ █░░ 
█▀▀▀ ▀▀▀▀ ▀▀▀ ▄▄▄█ ▀▀▀ ▀░▀▀ ▄▄▄█ ▀▀▀ ░░▀░░ ▀░░▀ ▀▀▀
*/


pragma solidity ^0.8.6;

import "./libraries/GibbonRouter.sol";
import "./BaseBaseStrategy.sol";


abstract contract BaseStrategy is BaseBaseStrategy {
    using SafeERC20 for IERC20;
    using GibbonRouter for AmmData;

    AmmData public constant APESWAP = AmmData.APE;
    
    address[] public earnedToMaticPath;
    
    AmmData public immutable farmAMM;
    
    constructor (AmmData _farmAMM, address _wantAddress, address _earnedAddress, address _vaultHealerAddress) 
        BaseBaseStrategy(_wantAddress, _earnedAddress, _vaultHealerAddress) {

        farmAMM = _farmAMM;
    }

    function buyBack(uint256 _earnedAmt) internal override returns (uint256) {
        
        if (_earnedAmt == 0 || buybackRate == 0) return _earnedAmt;
        
        uint256 buybackAmt = _earnedAmt * buybackRate / BASIS_POINTS;
    
        //often we can skip a lot of logic and just transfer CRYSTL
        if (earnedAddress == CRYSTL) {
            IERC20(CRYSTL).safeTransfer(buybackReceiver, buybackAmt);
        } else {
            uint wmaticAmt = farmAMM.swap(
                buybackAmt,
                earnedToMaticPath,
                address(this)
            );
    
            APESWAP.swap(
                wmaticAmt,
                WMATIC,
                CRYSTL,
                buybackReceiver
            );
        }
        
        return _earnedAmt - buybackAmt;
    }
    
}