// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "./Strategy.sol";
import "./interfaces/IDragonLair.sol";
import "@prb/math/contracts/PRBMath.sol";

contract StrategyWrapperToken is Strategy {
    using StrategyConfig for StrategyConfig.MemPointer;
    using Tactics for Tactics.TacticsA;
	using Fee for Fee.Data[3];

	error Strategy_MonotonicRatio(uint oldRatio, uint newRatio);
	event UpdateRatio(uint newRatio);
	
	uint constant PRECISION = 2**128;

	uint public underlyingRatioLast;
	
	function _initialSetup() internal override {
		require(config.earnedLength() == 0, "Earned tokens cannot be set on this strategy");
		underlyingRatioLast = getUnderlyingRatio();
		super._initialSetup();
	}
	
	function wrapperToken() internal pure returns (IERC20) {
		return IERC20(config.tacticsA().masterchef());
	}
	
	//If the wrapper token is a lending protocol such as Aave, this must be overridden, as it'll be missing the lent amount.
	function getUnderlyingTotal() internal virtual view returns (uint256) {
		return config.wantToken().balanceOf(address(wrapperToken()));
	}
	function getWrapperTotalSupply() internal virtual view returns (uint256) {
		return wrapperToken().totalSupply();
	}
	
	function getUnderlyingRatio() internal view returns (uint256) {
		return PRBMath.mulDiv(PRECISION, getUnderlyingTotal(), getWrapperTotalSupply());
	}
	
	//Typically the VST tactic should be configured using the standard balanceOf(address(this))
	function _vaultSharesTotal() internal view virtual override returns (uint256) {
		return PRBMath.mulDiv(super._vaultSharesTotal(), underlyingRatioLast, PRECISION);
	}
	
    function _earn(Fee.Data[3] calldata fees, address, bytes calldata) internal virtual override returns (bool success) {
        _sync();
        
		uint oldRatio = underlyingRatioLast;
		uint newRatio = getUnderlyingRatio();
		
		if (newRatio > oldRatio) {
			IERC20 wrapper = wrapperToken();
			uint wrapperBalance = wrapper.balanceOf(address(this));
			fees.payTokenFeePortion(wrapper, PRBMath.mulDiv(wrapperBalance, newRatio - oldRatio, oldRatio));
			success = true;
			underlyingRatioLast = newRatio;
			emit UpdateRatio(newRatio);
		} else if (newRatio < oldRatio) {
			revert Strategy_MonotonicRatio(oldRatio, newRatio);
		}
    }

    function generateConfig(
        Tactics.TacticsA _tacticsA,
        Tactics.TacticsB _tacticsB,
        address _wantToken,
        uint8 _wantDust,
        address _router,
        address _magnetite,
        uint8 _slippageFactor,
        bool _feeOnTransfer
    ) external view returns (bytes memory configData) {
        return generateConfig(_tacticsA, _tacticsB, _wantToken, _wantDust, _router, _magnetite, _slippageFactor, _feeOnTransfer, new address[](0), new uint8[](0));
    }
}