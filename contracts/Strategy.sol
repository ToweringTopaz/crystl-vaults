// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

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
    constructor(IVaultHealer _vaultHealer) BaseStrategy(_vaultHealer) {
        WETH_DUST = (block.chainid == 137 || block.chainid == 25) ? 1e18 : (block.chainid == 56 ? 1e16 : 1e14);
    }

    function earn(Fee.Data[3] calldata fees, address, bytes calldata) external virtual getConfig onlyVaultHealer guardPrincipal returns (bool success, uint256 __wantLockedTotal) {
        (IERC20 _wantToken,) = config.wantToken();

        //targetWant is the want token for standard vaults, or the want token of a maximizer's target
        IERC20 targetWant = config.isMaximizer() ? VaultChonk.strat(vaultHealer, config.vid() >> 16).wantToken() : _wantToken;
		uint targetWantBefore = targetWant.balanceOf(address(this)); 

        _vaultHarvest(); //Perform the harvest of earned reward tokens
        
        IWETH weth = config.weth();
        bool earnedTargetWant;
        for (uint i; i < config.earnedLength(); i++) { //In case of multiple reward vaults, process each reward token
            (IERC20 earnedToken, uint dust) = config.earned(i);

            uint256 earnedAmt = earnedToken.balanceOf(address(this));
            if (earnedAmt > dust) { //don't waste gas swapping minuscule rewards
                success = true; //We have something worth compounding

                if (earnedToken == targetWant) earnedTargetWant = true;
                else safeSwap(earnedAmt, earnedToken, weth); //swap to the native gas token if not the targetwant token
            }
        }
        if (!success && tx.origin != address(1)) return (false, _wantLockedTotal()); //a call from address(1) is for gas estimation
        uint wethAmt = weth.balanceOf(address(this));

        //pay fees on new targetWant tokens
        uint targetWantAmt;
        if (earnedTargetWant) {
            targetWantAmt = targetWant.balanceOf(address(this));
            targetWantAmt = fees.payTokenFeePortion(targetWant, targetWantAmt - targetWantBefore) + targetWantBefore;
        } else {
            targetWantAmt = targetWantBefore;
        }

        if (config.isMaximizer() && unwrapAll(weth)) {
            fees.payEthPortion(address(this).balance); //pays the fee portion
            try IVaultHealer(msg.sender).maximizerDeposit{value: address(this).balance}(config.vid(), targetWantAmt, "") { //deposit the rest, and any targetWant tokens
                return (true, _wantLockedTotal());
            }
            catch {  //compound want instead if maximizer doesn't work
                wethAmt = 0;
                success = false;
            }
        }
        //standard autocompound behavior
        wethAmt += wrapAll(weth);
        wethAmt = fees.payWethPortion(weth, wethAmt); //pay fee portion
        swapToWantToken(wethAmt, weth);
        __wantLockedTotal = _wantToken.balanceOf(address(this)) + _farm();
    }

    function wrapAll(IWETH weth) private returns (uint amountWrapped) {
         if (address(this).balance > WETH_DUST) {
             amountWrapped = address(this).balance;
             weth.deposit{value: address(this).balance}();
         }
    }
    function unwrapAll(IWETH weth) private returns (bool hasEth) {
        uint wethBal = weth.balanceOf(address(this));
        if (wethBal > WETH_DUST) {
            weth.withdraw(wethBal);
            return true;
        }
        return address(this).balance > WETH_DUST;
    }

    //VaultHealer calls this to add funds at a user's direction. VaultHealer manages the user shares
    function deposit(uint256 _wantAmt, uint256 _sharesTotal, bytes calldata) external virtual payable getConfig onlyVaultHealer guardPrincipal returns (uint256 wantAdded, uint256 sharesAdded) {
        (IERC20 _wantToken,) = config.wantToken();
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
        uint vaultSharesAfter = _farm(); //deposits the tokens in the pool
        // Proper deposit amount for tokens with fees, or vaults with deposit fees

        wantAdded = _wantToken.balanceOf(address(this)) + vaultSharesAfter - wantLockedBefore;
        sharesAdded = _sharesTotal == 0 ? wantAdded : Math.ceilDiv(wantAdded * _sharesTotal, wantLockedBefore);
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

		uint withdrawSlippage = 0;
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