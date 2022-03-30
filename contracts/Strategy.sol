// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import "./BaseStrategy.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
//This is a strategy contract which can be expected to support 99% of pools. Tactic contracts provide the pool interface.
contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using StrategyConfig for StrategyConfig.MemPointer;
    using Fee for Fee.Data[3];

    constructor(IVaultHealer _vaultHealer) BaseStrategy(_vaultHealer) {}

    function earn(Fee.Data[3] calldata fees, address, bytes calldata) external virtual getConfig onlyVaultHealer returns (bool success, uint256 __wantLockedTotal) {
        (IERC20 _wantToken,) = config.wantToken();
        uint wantBalanceBefore = _wantToken.balanceOf(address(this)); //Don't sell starting want balance (anti-rug)
        _vaultHarvest();

        IWETH weth = config.weth();
        uint earnedLength = config.earnedLength();

        for (uint i; i < earnedLength; i++) {
            (IERC20 earnedToken, uint dust) = config.earned(i);

            uint256 earnedAmt = earnedToken.balanceOf(address(this));
            if (earnedToken == _wantToken) earnedAmt -= wantBalanceBefore; //ignore pre-existing want tokens
            if (earnedAmt < dust) continue; //not enough of this token earned to continue with a swap
            
            success = true; //We have something worth compounding
            safeSwap(earnedAmt, earnedToken, weth); //swap all earned tokens to weth (native token)
        }
        if (!success) return (false, _wantLockedTotal()); //Nothing to do because harvest
        uint wethAdded = weth.balanceOf(address(this));
        if (_wantToken == weth) wethAdded -= wantBalanceBefore; //ignore pre-existing want tokens
        if (config.isMaximizer()) {
            weth.withdraw(wethAdded); //unwrap wnative token
            uint ethToTarget = fees.payEthPortion(address(this).balance); //pays the fee portion, returns the amount after fees
            try IVaultHealer(msg.sender).maximizerDeposit{value: ethToTarget}(config.vid(), 0, "") {} //deposit the rest
            catch {  //compound want instead if maximizer doesn't work
                weth.deposit{value: ethToTarget}();
                swapToWantToken(ethToTarget, weth);
            }
        } else {
            wethAdded = fees.payWethPortion(weth, wethAdded); //pay fee portion
            swapToWantToken(wethAdded, weth);

            _farm();
        }

        __wantLockedTotal = _wantLockedTotal();
    }

    //VaultHealer calls this to add funds at a user's direction. VaultHealer manages the user shares
    function deposit(uint256 _wantAmt, uint256 _sharesTotal, bytes calldata) external virtual payable getConfig onlyVaultHealer returns (uint256 wantAdded, uint256 sharesAdded) {
        (IERC20 _wantToken, uint dust) = config.wantToken();
        uint wantBal = _wantToken.balanceOf(address(this));
        uint wantLockedBefore = wantBal + _vaultSharesTotal();

        if (msg.value > 0) {
            IWETH weth = config.weth();
            weth.deposit{value: msg.value}();
            swapToWantToken(msg.value, weth);
        }

        //Before calling deposit here, the vaulthealer records how much the user deposits. Then with this
        //call, the strategy tells the vaulthealer to proceed with the transfer. This minimizes risk of
        //a rogue strategy 
        if (_wantAmt > 0) IVaultHealer(msg.sender).executePendingDeposit(address(this), uint192(_wantAmt));
        _farm(); //deposits the tokens in the pool
        // Proper deposit amount for tokens with fees, or vaults with deposit fees

        wantAdded = _wantToken.balanceOf(address(this)) + _vaultSharesTotal() - wantLockedBefore;
        sharesAdded = wantAdded;
        if (_sharesTotal > 0) { 
            sharesAdded = Math.ceilDiv(sharesAdded * _sharesTotal, wantLockedBefore);
        }
        if (wantAdded < dust) revert Strategy_DustDeposit(wantAdded);
    }


    //Correct logic to withdraw funds, based on share amounts provided by VaultHealer
    function withdraw(uint _wantAmt, uint _userShares, uint _sharesTotal, bytes calldata) external virtual getConfig onlyVaultHealer returns (uint sharesRemoved, uint wantAmt) {
        (IERC20 _wantToken, uint dust) = config.wantToken();
        uint wantBal = _wantToken.balanceOf(address(this)); 
        uint wantLockedBefore = wantBal + _vaultSharesTotal();
        uint256 userWant = _userShares * wantLockedBefore / _sharesTotal; //User's balance, in want tokens
        
        // user requested all, very nearly all, or more than their balance, so withdraw all
        unchecked { //overflow is caught and handled in the second condition
            if (_wantAmt + dust > userWant || _wantAmt + dust < _wantAmt) {
				_wantAmt = userWant;
            }
        }

		uint withdrawSlippage;
        if (_wantAmt > wantBal) {
            _vaultWithdraw(_wantToken, _wantAmt - wantBal); //Withdraw from the masterchef, staking pool, etc.
            wantBal = _wantToken.balanceOf(address(this));
			uint wantLockedAfter = wantBal + _vaultSharesTotal();
			
			//Account for reflect, pool withdraw fee, etc; charge these to user
			withdrawSlippage = wantLockedAfter < wantLockedBefore ? wantLockedBefore - wantLockedAfter : 0;
		} else {
			withdrawSlippage = 0;
		}
		
		//Calculate shares to remove
        sharesRemoved = Math.ceilDiv(
            (_wantAmt + withdrawSlippage) * _sharesTotal,
            wantLockedBefore
        );
		
        //Get final withdrawal amount
        if (sharesRemoved > _userShares) {
            sharesRemoved = _userShares;
        }
		wantAmt = sharesRemoved * wantLockedBefore / _sharesTotal;
		if (wantAmt > withdrawSlippage) {
			wantAmt -= withdrawSlippage;
			if (wantAmt > wantBal) wantAmt = wantBal;
		} else {
			revert Strategy_TotalSlippageWithdrawal(); //nothing to withdraw after slippage
		}

        return (sharesRemoved, wantAmt);

    }

    function generateConfig(
        Tactics.TacticsA _tacticsA,
        Tactics.TacticsB _tacticsB,
        address _wantToken,
        uint8 _wantDust,
        address _router,
        address _magnetite,
        uint8 _slippageFactor,
        bool _feeOnTransfer,
        address[] memory _earned,
        uint8[] memory _earnedDust
    ) external view returns (bytes memory configData) {
        require(_earned.length > 0 && _earned.length < 0x20, "earned.length invalid");
        require(_earned.length == _earnedDust.length, "earned/dust length mismatch");
        uint8 vaultType = uint8(_earned.length);
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

        for (uint i; i < _earned.length; i++) {
            configData = abi.encodePacked(configData, _earned[i], _earnedDust[i]);
        }

        configData = abi.encodePacked(configData, IUniRouter(_router).WETH());
    }

    function generateTactics(
        address _masterchef,
        uint24 pid, 
        uint8 vstReturnPosition, 
        uint64 vstCode, //includes selector and encoded call format
        uint64 depositCode, //includes selector and encoded call format
        uint64 withdrawCode, //includes selector and encoded call format
        uint64 harvestCode, //includes selector and encoded call format
        uint64 emergencyCode//includes selector and encoded call format
    ) external pure returns (Tactics.TacticsA tacticsA, Tactics.TacticsB tacticsB) {
        assembly ("memory-safe") {
            tacticsA := or(or(shl(96, _masterchef), shl(72, pid)), or(shl(64, vstReturnPosition), vstCode))
            tacticsB := or(or(shl(192, depositCode), shl(128, withdrawCode)), or(shl(64, harvestCode), emergencyCode))
        }
    }

}