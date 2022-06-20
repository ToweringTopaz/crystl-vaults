// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "./BaseStrategy.sol";
import "./libraries/VaultChonk.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./libraries/VaultChonk.sol";

//This is a strategy contract which can be expected to support 99% of pools. Tactic contracts provide the pool interface.
contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using StrategyConfig for StrategyConfig.MemPointer;
    using Fee for Fee.Data[3];
    using VaultChonk for IVaultHealer;

    uint immutable WETH_DUST;

    event Strategy_MaximizerDepositFailure();

    constructor(IVaultHealer _vaultHealer) BaseStrategy(_vaultHealer) {
        WETH_DUST = (block.chainid == 137 || block.chainid == 25) ? 1e18 : (block.chainid == 56 ? 1e16 : 1e14);
    }

    function earn(Fee.Data[3] calldata fees, address op, bytes calldata data) public virtual getConfig onlyVaultHealer guardPrincipal returns (bool success, uint256 __wantLockedTotal) {
        return config.isMaximizer() ? _earnMaximizer(fees, op, data) : _earnAutocompound(fees, op, data);
    }

    function _earnAutocompound(Fee.Data[3] calldata fees, address, bytes calldata) internal returns (bool success, uint256 __wantLockedTotal) {
        _vaultSync();
        IERC20 _wantToken = config.wantToken();
		uint wantAmt = _wantToken.balanceOf(address(this)); 

        _vaultHarvest(); //Perform the harvest of earned reward tokens
        
        for (uint i; i < config.earnedLength(); i++) { //In case of multiple reward vaults, process each reward token
            (IERC20 earnedToken, uint dust) = config.earned(i);

            uint256 earnedAmt = earnedToken.balanceOf(address(this));
            if (earnedAmt > dust) { //don't waste gas swapping minuscule rewards
                if (earnedToken == _wantToken) continue;

                IERC20[] memory path;
                bool toWeth;
                if (config.isPairStake()) {
                    (IERC20 token0, IERC20 token1) = config.token0And1();
                    (toWeth, path) = wethOnPath(earnedToken, token0);
                    (bool toWethToken1,) = wethOnPath(earnedToken, token1);
                    toWeth = toWeth && toWethToken1;
                } else {
                    (toWeth, path) = wethOnPath(earnedToken, _wantToken);
                }
                if (toWeth) safeSwap(earnedAmt, path); //swap to the native gas token if it's on the path
                else swapToWantToken(earnedAmt, earnedToken);
            }
        }
        uint wantBalance = _wantToken.balanceOf(address(this));        
        if (wantBalance > config.wantDust()) {
            wantAmt = fees.payTokenFeePortion(_wantToken, wantBalance - wantAmt) + wantAmt; //fee portion on newly obtained want tokens
            success = true;
        }
        if (unwrapAllWeth()) {
            fees.payEthPortion(address(this).balance); //pays the fee portion
            uint wethAmt = address(this).balance;
            wrapAllEth();
            swapToWantToken(wethAmt, config.weth());
            success = true;
        }
        __wantLockedTotal = _wantToken.balanceOf(address(this)) + (success ? _farm() : _vaultSharesTotal());
        _vaultSwim();
    }

    function _earnMaximizer(Fee.Data[3] calldata fees, address, bytes calldata) internal returns (bool success, uint256 __wantLockedTotal) {
        //targetWant is the want token for standard vaults, or the want token of a maximizer's target
        ConfigInfo memory targetConfig = VaultChonk.strat(msg.sender/*vaultHealer*/, config.vid() >> 16).configInfo();
        IERC20 targetWant = targetConfig.want;
		uint targetWantAmt = targetWant.balanceOf(address(this)); 

        _vaultHarvest(); //Perform the harvest of earned reward tokens
        
        for (uint i; i < config.earnedLength(); i++) { //In case of multiple reward vaults, process each reward token
            (IERC20 earnedToken, uint dust) = config.earned(i);

            if (earnedToken != targetWant) {
                uint256 earnedAmt = earnedToken.balanceOf(address(this));
                if (earnedAmt > dust) { //don't waste gas swapping minuscule rewards
                    safeSwap(earnedAmt, earnedToken, config.weth()); //swap to the native gas token if not the targetwant token
                }
            }
        }

        uint targetWantBalance = targetWant.balanceOf(address(this));        
        if (targetWantBalance > targetConfig.wantDust) {
            targetWantAmt = fees.payTokenFeePortion(targetWant, targetWantBalance - targetWantAmt) + targetWantAmt;
            success = true;
        }
        if (unwrapAllWeth()) {
            fees.payEthPortion(address(this).balance); //pays the fee portion
            success = true;
        }

        if (success) {
            
            try IVaultHealer(msg.sender).maximizerDeposit{value: address(this).balance}(config.vid(), targetWantAmt, "") {} //deposit the rest, and any targetWant tokens
            catch {  //compound want instead if maximizer doesn't work
                wrapAllEth();
                IWETH weth = config.weth();
                uint wethAmt = weth.balanceOf(address(this));
                if (wethAmt > WETH_DUST) {
                    wethAmt = fees.payWethPortion(weth, wethAmt); //pay fee portion
                    swapToWantToken(wethAmt, weth);
                } else if (targetWantAmt > 0 && targetWant != config.wantToken()) {
                    swapToWantToken(targetWantAmt, targetWant);
                }
                emit Strategy_MaximizerDepositFailure();
            }
        }

        __wantLockedTotal = config.wantToken().balanceOf(address(this)) + _farm();
        _vaultSwim();
    }

    function wrapAllEth() private {
        if (address(this).balance > WETH_DUST) {
            config.weth().deposit{value: address(this).balance}();
        }
    }
    function unwrapAllWeth() private returns (bool hasEth) {
        IWETH weth = config.weth();
        uint wethBal = weth.balanceOf(address(this));
        if (wethBal > WETH_DUST) {
            weth.withdraw(wethBal);
            return true;
        }
        return address(this).balance > WETH_DUST;
    }

    //VaultHealer calls this to add funds at a user's direction. VaultHealer manages the user shares
    function deposit(uint256 _wantAmt, uint256 _sharesTotal, bytes calldata) public virtual payable getConfig onlyVaultHealer returns (uint256 wantAdded, uint256 sharesAdded) {
        _vaultSync();
        IERC20 _wantToken = config.wantToken();
        uint wantLockedBefore = _farm() + _wantToken.balanceOf(address(this));

        if (msg.value > 0) {
            IWETH weth = config.weth();
            weth.deposit{value: msg.value}();
            swapToWantToken(msg.value, weth);
        }

        //Before calling deposit here, the vaulthealer records how much the user deposits. Then with this
        //call, the strategy tells the vaulthealer to proceed with the transfer. This minimizes risk of
        //a rogue strategy 
        if (_wantAmt > 0) IVaultHealer(msg.sender).executePendingDeposit(address(this), uint192(_wantAmt));
        uint vaultSharesAfter = _farm(); //deposits the tokens in the pool
        // Proper deposit amount for tokens with fees, or vaults with deposit fees

        wantAdded = _wantToken.balanceOf(address(this)) + vaultSharesAfter - wantLockedBefore;
        sharesAdded = _sharesTotal == 0 ? wantAdded : Math.ceilDiv(wantAdded * _sharesTotal, wantLockedBefore);
        if (wantAdded < config.wantDust() || sharesAdded == 0) revert Strategy_DustDeposit(wantAdded);
        _vaultSwim();
    }


    //Correct logic to withdraw funds, based on share amounts provided by VaultHealer
    function withdraw(uint _wantAmt, uint _userShares, uint _sharesTotal, bytes calldata) public virtual getConfig onlyVaultHealer returns (uint sharesRemoved, uint wantAmt) {
        IERC20 _wantToken = config.wantToken();
        uint wantBal = _wantToken.balanceOf(address(this));
        _vaultSync(); //updates balance on underlying pool, if necessary
        uint wantLockedBefore = wantBal + _vaultSharesTotal();
        uint256 userWant = _userShares * wantLockedBefore / _sharesTotal; //User's balance, in want tokens
        
        // user requested all, very nearly all, or more than their balance, so withdraw all
        unchecked { //overflow is caught and handled in the second condition
            uint dust = config.wantDust();
            if (_wantAmt + dust > userWant || _wantAmt + dust < _wantAmt) {
				_wantAmt = userWant;
            }
        }

		uint withdrawSlippage;
        if (_wantAmt > wantBal) {
            uint toWithdraw = _wantAmt - wantBal;
            _vaultWithdraw(_wantToken, toWithdraw); //Withdraw from the masterchef, staking pool, etc.
            wantBal = _wantToken.balanceOf(address(this));
			uint wantLockedAfter = wantBal + _vaultSharesTotal();
			
			//Account for reflect, pool withdraw fee, etc; charge these to user
			withdrawSlippage = wantLockedAfter < wantLockedBefore ? wantLockedBefore - wantLockedAfter : 0;
		}
		
		//Calculate shares to remove
        sharesRemoved = (_wantAmt + withdrawSlippage) * _sharesTotal;
        sharesRemoved = Math.ceilDiv(sharesRemoved, wantLockedBefore);
		
        //Get final withdrawal amount
        if (sharesRemoved > _userShares) {
            sharesRemoved = _userShares;
        }
		wantAmt = sharesRemoved * wantLockedBefore / _sharesTotal;
        
        if (wantAmt <= withdrawSlippage) revert Strategy_TotalSlippageWithdrawal(); //nothing to withdraw after slippage
		
		wantAmt -= withdrawSlippage;
		if (wantAmt > wantBal) wantAmt = wantBal;
		
        _vaultSwim();
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
        bool _metaVault,
        address[] calldata _earned,
        uint8[] calldata _earnedDust
    ) external view returns (bytes memory configData) {
        require(_earned.length > 0 && _earned.length < 0x20, "earned.length invalid");
        require(_earned.length == _earnedDust.length, "earned/dust length mismatch");
        uint8 vaultType = uint8(_earned.length);
        if (_feeOnTransfer) vaultType += 0x80;
        if (_metaVault) vaultType += 0x40;
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
        bytes8 vstCode, //includes selector and encoded call format
        bytes8 depositCode, //includes selector and encoded call format
        bytes8 withdrawCode, //includes selector and encoded call format
        bytes8 harvestCode, //includes selector and encoded call format
        bytes8 emergencyCode//includes selector and encoded call format
    ) external pure returns (Tactics.TacticsA tacticsA, Tactics.TacticsB tacticsB) {
        tacticsA = Tactics.TacticsA.wrap(bytes32(abi.encodePacked(bytes20(_masterchef),bytes3(pid),bytes1(vstReturnPosition),vstCode)));
        tacticsB = Tactics.TacticsB.wrap(bytes32(abi.encodePacked(depositCode, withdrawCode, harvestCode, emergencyCode)));
    }

}