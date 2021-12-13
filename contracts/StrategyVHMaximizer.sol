// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./BaseStrategyVaultHealer.sol";
import "./libs/ITactic.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

//This is a strategy contract which can be expected to support 99% of pools. Tactic contracts provide the pool interface.
contract StrategyVHMaximizer is BaseStrategyVaultHealer, ERC1155Holder {
    using Address for address;
    using SafeERC20 for IERC20;
    using LibVaultConfig for VaultFees;
    using LibVaultSwaps for VaultFees;

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
        IERC20[] memory _earned,
        address _maximizerVault,
        address _maximizerRewardToken
    )
        BaseStrategy(_settings)
        BaseStrategySwapLogic(_wantToken, _earned)
        BaseStrategyVaultHealer(_vaultHealerAddress)
    {
        masterchef = _masterchefAddress;
        tactic = ITactic(_tacticAddress);
        pid = _pid;
        maximizerVault = IStrategy(_maximizerVault);
        maximizerRewardToken = IERC20(_maximizerRewardToken);
        // maximizerVault.setFees(
        //                 [
        //         [ ZERO_ADDRESS, FEE_ADDRESS, 0 ], // withdraw fee: token is not set here; standard fee address; 10 now means 0.1% consistent with other fees
        //         [ WMATIC, FEE_ADDRESS, 0 ], //earn fee: wmatic is paid; goes back to caller of earn; 0% rate
        //         [ WMATIC, FEE_ADDRESS, 0 ], //reward fee: paid in DAI; standard fee address; 0% rate
        //         [ CRYSTL, BURN_ADDRESS, 0 ] //burn fee: crystl to burn address; 5% rate
        //     ]
        // );
        isMaximizer = true;
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
                earnedAmt = vaultFees.distribute(settings, vaultStats, earnedToken, earnedAmt, _to); // handles all fees for this earned token
                // Swap earned to crystl for maximizer
                LibVaultSwaps.safeSwap(settings, earnedAmt, earnedToken, IERC20(0x76bF0C28e604CC3fE9967c83b3C3F31c213cfE64), address(this)); //todo: change this from a hardcoding
            }
        }

        if (success) {
            // deposits the tokens into the crystl vault
            // _farm();
            IERC20 crystlToken = IERC20(0x76bF0C28e604CC3fE9967c83b3C3F31c213cfE64); //todo: change this from a hardcoding
            uint256 crystlBalance = crystlToken.balanceOf(address(this));

            //need to instantiate pool here?
            crystlToken.safeApprove(address(vaultHealer), crystlBalance);

            vaultHealer.deposit(3, crystlBalance); //pid can be hardcoded here? let's say for now that it's 1?
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