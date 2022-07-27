// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "./BaseStrategy.sol";
import "./MaximizerStrategy.sol";

//Standard v3 Strategy
contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using StrategyConfig for StrategyConfig.MemPointer;
    using Fee for Fee.Data[3];
    using VaultChonk for IVaultHealer;

    IStrategy immutable _maximizerImplementation;

    constructor() {
        _maximizerImplementation = _deployMaximizerImplementation();
	}

    function _deployMaximizerImplementation() internal virtual returns (IStrategy) {
        return new MaximizerStrategy();
    }

    function getMaximizerImplementation() external virtual override view returns (IStrategy) {
        return _maximizerImplementation;
    }

    function _earn(Fee.Data[3] calldata fees, address, bytes calldata) internal virtual override returns (bool success) {
        _sync();        
        IERC20 _wantToken = config.wantToken();
		uint wantAmt = _wantToken.balanceOf(address(this)); 

        _vaultHarvest(); //Perform the harvest of earned reward tokens
        
        for (uint i; i < config.earnedLength(); i++) { //In case of multiple reward vaults, process each reward token
            (IERC20 earnedToken, uint dust) = config.earned(i);

            if (earnedToken != _wantToken) {
                uint256 earnedAmt = earnedToken.balanceOf(address(this));
                //don't waste gas swapping minuscule rewards
                if (earnedAmt > dust) sellUnwanted(earnedToken, earnedAmt);
            }
        }

        uint wantHarvested = _wantToken.balanceOf(address(this)) - wantAmt;
        if (wantHarvested > config.wantDust()) {
            wantAmt = fees.payTokenFeePortion(_wantToken, wantHarvested) + wantAmt; //fee portion on newly obtained want tokens
            success = true;
        }
        if (unwrapAllWeth()) {
            fees.payEthPortion(address(this).balance); //pays the fee portion
            uint wethAmt = address(this).balance;
            wrapAllEth();
            swapToWantToken(wethAmt, config.weth());
            success = true;
        }
        if (success) _farm();
    }

}