// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./BaseStrategyVaultHealer.sol";
import "./libs/ITactic.sol";

//This is a strategy contract which can be expected to support 99% of pools. Tactic contracts provide the pool interface.
contract StrategyVHMaximizer is BaseStrategyVaultHealer {
    using Address for address;
    using SafeERC20 for IERC20;
    
    address public immutable masterchef;
    ITactic public immutable tactic;
    uint public immutable pid;

    constructor(
        IERC20 _wantToken,
        address _vaultHealerAddress,
        address _masterchefAddress,
        address _tacticAddress,
        uint256 _pid,
        VaultSettings memory _settings,
        IERC20[] memory _earned
    )
        BaseStrategy(_settings)
        BaseStrategySwapLogic(_wantToken, _earned)
        BaseStrategyVaultHealer(_vaultHealerAddress)
    {
        masterchef = _masterchefAddress;
        tactic = ITactic(_tacticAddress);
        pid = _pid;
    }
    
    function _earn(address _to) internal override whenEarnIsReady {
        
        uint wantBalanceBefore = _wantBalance(); //Don't touch starting want balance (anti-rug)
        _vaultHarvest(); // Harvest farm tokens

        uint dust = settings.dust; //minimum number of tokens to bother trying to compound
        bool success;
        
        for (uint i; i < earnedLength; i++) { //Process each earned token, whether it's 1, 2, or 8. 
            IERC20 earnedToken = earned[i];
            uint256 earnedAmt = earnedToken.balanceOf(address(this));
            if (earnedToken == wantToken)
                earnedAmt -= wantBalanceBefore; //ignore pre-existing want tokens
                
            if (earnedAmt > dust) {
                success = true; //We have something worth compounding
                // earnedAmt = vaultFees.distribute(settings, vaultStats, earnedToken, earnedAmt, _to); // handles all fees for this earned token
                // Swap earned to crystl for maximizer
                LibVaultSwaps.safeSwap(settings, earnedAmt, earnedToken, IERC20(0x76bF0C28e604CC3fE9967c83b3C3F31c213cfE64), address(this));
            }
        }

        if (success) {
            // deposits the tokens into the crystl vault
            // _farm();
            IERC20 crystlToken = IERC20(0x76bF0C28e604CC3fE9967c83b3C3F31c213cfE64); //can hardcode the crystl address in here?
            uint256 crystlBalance = crystlToken.balanceOf(address(this));
            //need to instantiate pool here?
            vaultHealer.deposit(1, crystlBalance); //pid can be hardcoded here? let's say for now that it's 1?
            // uint256 sharesAdded = pool.strat.deposit(msg.sender, _to, crystlBalance, totalSupply(_pid)); //need to pass in from, to, sharesTotal - which sharesTotal? sharesTotal of strat A in strat B?
        }
        lastEarnBlock = block.number;
    }
    
    function vaultSharesTotal() public override view returns (uint256) {
        return tactic.vaultSharesTotal(masterchef, pid);
    }
    
    function _vaultDeposit(uint256 _amount) internal override {
        
        //token allowance for the pool to pull the correct amount of funds only
        wantToken.safeIncreaseAllowance(masterchef, _amount);
        
        address(tactic).functionDelegateCall(abi.encodeWithSelector(
            tactic._vaultDeposit.selector, masterchef, pid, _amount
        ), "vaultdeposit failed");
    }
    
    function _vaultWithdraw(uint256 _amount) internal override {
        address(tactic).functionDelegateCall(abi.encodeWithSelector(
            tactic._vaultWithdraw.selector, masterchef, pid, _amount
        ), "vaultwithdraw failed");
    }
    
    function _vaultHarvest() internal override {
        address(tactic).functionDelegateCall(abi.encodeWithSelector(
            tactic._vaultHarvest.selector, masterchef, pid
        ), "vaultharvest failed");
    }
    
    function _emergencyVaultWithdraw() internal override {
        address(tactic).functionDelegateCall(abi.encodeWithSelector(
            tactic._emergencyVaultWithdraw.selector, masterchef, pid
        ), "emergencyvaultwithdraw failed");
    }
        
}