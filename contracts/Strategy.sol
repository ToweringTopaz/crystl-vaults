// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./BaseStrategy.sol";
import "./libraries/LibQuartz.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

//This is a strategy contract which can be expected to support 99% of pools. Tactic contracts provide the pool interface.
contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using StrategyConfig for StrategyConfig.MemPointer;

    constructor(address _vaultHealer) BaseStrategy(_vaultHealer) {}

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
        uint8[] memory _earnedDust,
        uint _targetVid
    ) external view returns (bytes memory configData) {
        require(_earned.length > 0 && _earned.length < 0x20, "earned.length invalid");
        require(_earned.length == _earnedDust.length, "earned/dust length mismatch");

        uint _vid;
        IERC20 _targetWant = IERC20(_wantToken);
        if (_targetVid > 0) {
            (_targetWant,,,_vid,) = IVaultHealer(vaultHealer).vaultInfo(_targetVid); //numMaximizers
            _vid |= (_targetVid << 32);
        } else {
            _vid = uint(IVaultHealer(vaultHealer).nextVid());
        }

        uint8 vaultType = uint8(_earned.length);
        if (_feeOnTransfer) vaultType += 0x80;
        
        configData = abi.encodePacked(_tacticsA, _tacticsB, _wantToken, _wantDust, _router, _magnetite, _slippageFactor);
        
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
    }

    function earn(Fee.Data[3] calldata fees) external virtual getConfig onlyVaultHealer returns (bool success, uint256 __wantLockedTotal) {
        (IERC20 _wantToken,) = config.wantToken();
        uint wantBalanceBefore = _wantToken.balanceOf(address(this)); //Don't sell starting want balance (anti-rug)

        (Tactics.TacticsA tacticsA, Tactics.TacticsB tacticsB) = config.tactics();
        Tactics.harvest(tacticsA, tacticsB); // Harvest farm tokens
        
        uint earnedLength = config.earnedLength();
        bool pairStake = config.isPairStake();

        for (uint i; i < earnedLength; i++) { //Process each earned token

            (IERC20 earnedToken, uint dust) = config.earned(i);
            uint256 earnedAmt = earnedToken.balanceOf(address(this));
            if (earnedToken == _wantToken)
                earnedAmt -= wantBalanceBefore; //ignore pre-existing want tokens

            if (earnedAmt > dust) {
                success = true; //We have something worth compounding
                earnedAmt = distribute(fees, earnedToken, earnedAmt); // handles all fees for this earned token

                if (pairStake) {
                    (IERC20 token0, IERC20 token1) = config.token0And1();
                    safeSwap(earnedAmt / 2, earnedToken, token0, address(this));
                    safeSwap(earnedAmt / 2, earnedToken, token1, address(this));
                } else {
                    safeSwap(earnedAmt, earnedToken, config.targetWant(), address(this));
                }
            }
        }

        //lpTokenLength == 1 means single-stake, not LP
        if (success) {
            if (config.isMaximizer()) {
                uint256 maximizerRewardBalance = config.targetWant().balanceOf(address(this));

                IVaultHealer(msg.sender).deposit(config.targetVid(), maximizerRewardBalance);
            } else { 
                if (pairStake) {
                    // Get want tokens, ie. add liquidity
                    (IERC20 token0, IERC20 token1) = config.token0And1();
                    LibQuartz.optimalMint(IUniPair(address(_wantToken)), token0, token1);
                }
                _farm();
            }
        }
        __wantLockedTotal = _wantLockedTotal();
    }

    //VaultHealer calls this to add funds at a user's direction. VaultHealer manages the user shares
    function deposit(uint256 _wantAmt, uint256 _sharesTotal) external virtual getConfig onlyVaultHealer returns (uint256 wantAdded, uint256 sharesAdded) {
        (IERC20 _wantToken, uint dust) = config.wantToken();
        uint wantBal = _wantToken.balanceOf(address(this));
        uint wantLockedBefore = wantBal + _vaultSharesTotal();

        if (_wantAmt < dust) return (0, 0); //do nothing if nothing is requested

        //Before calling deposit here, the vaulthealer records how much the user deposits. Then with this
        //call, the strategy tells the vaulthealer to proceed with the transfer. This minimizes risk of
        //a rogue strategy 
        IVaultHealer(msg.sender).executePendingDeposit(address(this), uint112(_wantAmt));
        _farm(); //deposits the tokens in the pool
        // Proper deposit amount for tokens with fees, or vaults with deposit fees
        wantAdded = _wantToken.balanceOf(address(this)) + _vaultSharesTotal() - wantLockedBefore;
        sharesAdded = wantAdded;
        if (_sharesTotal > 0) { 
            sharesAdded = Math.ceilDiv(sharesAdded * _sharesTotal, wantLockedBefore);
        }
        require(sharesAdded > dust, "deposit: no/dust shares added");
    }


    //Correct logic to withdraw funds, based on share amounts provided by VaultHealer
    function withdraw(uint _wantAmt, uint _userShares, uint _sharesTotal) external virtual getConfig onlyVaultHealer returns (uint sharesRemoved, uint wantAmt) {
        (IERC20 _wantToken, uint dust) = config.wantToken();
        //User's balance, in want tokens
        uint wantBal = _wantToken.balanceOf(address(this)); ///todo: why would there be want sitting in the strat contract?
        uint wantLockedBefore = wantBal + _vaultSharesTotal(); //todo: why is this different to deposit function????????????
        uint256 userWant = _userShares * wantLockedBefore / _sharesTotal;
        
        // user requested all, very nearly all, or more than their balance, so withdraw all
        if (_wantAmt + dust > userWant) {
            _wantAmt = userWant;
        }
        
        // Check if strategy has tokens from panic
        if (_wantAmt > wantBal) {
            (Tactics.TacticsA tacticsA, Tactics.TacticsB tacticsB) = config.tactics();
            Tactics.withdraw(tacticsA, tacticsB, _wantAmt - wantBal);
            
            wantBal = _wantToken.balanceOf(address(this));
        }

        //Account for reflect, pool withdraw fee, etc; charge these to user
        uint wantLockedAfter = _wantToken.balanceOf(address(this)) + _vaultSharesTotal();
        uint withdrawSlippage = wantLockedAfter < wantLockedBefore ? wantLockedBefore - wantLockedAfter : 0;

        //Calculate shares to remove
        sharesRemoved = Math.ceilDiv(
            (_wantAmt + withdrawSlippage) * _sharesTotal,
            wantLockedBefore
        );

        //Get final withdrawal amount
        if (sharesRemoved > _userShares) {
            sharesRemoved = _userShares;
        }

        _wantAmt = Math.ceilDiv(sharesRemoved * wantLockedBefore, _sharesTotal) - withdrawSlippage;
        if (_wantAmt > wantBal) _wantAmt = wantBal;

        require(_wantAmt > 0, "nothing to withdraw after slippage");
        
        return (sharesRemoved, _wantAmt);
    }    

}