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

	uint public underlyingRatioLast;
	
	function _initialSetup() internal override {
		require(config.earnedLength() == 0, "Earned tokens cannot be set on this strategy");
		super._initialSetup();
	}
	
	function wrapperToken() internal view returns (IERC20) {
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
		return PRBMath.mulDiv(2**128, getUnderlyingTotal(), getWrapperTotalSupply());
	}
	
	//Typically the VST tactic should be configured using the standard balanceOf(address(this))
	function _vaultSharesTotal() internal view virtual override returns (uint256) {
		return PRBMath.mulDiv(super._vaultSharesTotal(), getUnderlyingTotal(), getWrapperTotalSupply());
	}
	
    function _earn(Fee.Data[3] calldata fees, address, bytes calldata) internal virtual override returns (bool success) {
        _sync();        
        IERC20 _wantToken = config.wantToken();
		uint wantAmt = _wantToken.balanceOf(address(this)); 
        
		uint oldRatio = underlyingRatioLast;
		uint newRatio = getUnderlyingRatio();
		
		if (newRatio > oldRatio) {
			IERC20 wrapper = wrapperToken();
			uint wrapperBalance = wrapper.balanceOf(address(this));
			fees.payTokenFeePortion(wrapper, PRBMath.mulDiv(wrapperBalance, newRatio - oldRatio, 2**128));
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
    ) external override view returns (bytes memory configData) {
        uint8 vaultType;
        if (_feeOnTransfer) vaultType += 0x80;
        configData = abi.encodePacked(_tacticsA, _tacticsB, _wantToken, _wantDust, _router, _magnetite, _slippageFactor);
		
		IERC20 _targetWant = IERC20(_wantToken);

        //Look for LP tokens. If not, want must be a single-stake
        try IUniPair(address(_targetWant)).token0() returns (IERC20 _token0) {
            vaultType += 0x20;
            IERC20 _token1 = IUniPair(address(_targetWant)).token1();
            configData = abi.encodePacked(configData, vaultType, _token0, _token1);
        } catch { //if not LP, then single stake
            configData = abi.encodePacked(configData, vaultType);
        }

        configData = abi.encodePacked(configData, IUniRouter(_router).WETH());
    }
}