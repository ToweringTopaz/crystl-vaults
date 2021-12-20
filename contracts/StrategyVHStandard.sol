// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./BaseStrategyVaultHealer.sol";
import "./libs/ITactic.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

//This is a strategy contract which can be expected to support 99% of pools. Tactic contracts provide the pool interface.
contract StrategyVHStandard is BaseStrategyVaultHealer, ERC1155Holder {
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
        address _targetVault //maximizer target
    )
        BaseStrategy(_settings, _vaultHealerAddress)
        BaseStrategySwapLogic(_wantToken, _earned, _targetVault)
    {
        masterchef = _masterchefAddress;
        pid = _pid;
        tactic = ITactic(_tacticAddress);

        // maximizerVault.setFees(
        //                 [
        //         [ ZERO_ADDRESS, FEE_ADDRESS, 0 ], // withdraw fee: token is not set here; standard fee address; 10 now means 0.1% consistent with other fees
        //         [ WMATIC, FEE_ADDRESS, 0 ], //earn fee: wmatic is paid; goes back to caller of earn; 0% rate
        //         [ WMATIC, FEE_ADDRESS, 0 ], //reward fee: paid in DAI; standard fee address; 0% rate
        //         [ CRYSTL, BURN_ADDRESS, 0 ] //burn fee: crystl to burn address; 5% rate
        //     ]
        // );
        
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

    function getMaximizerRewardToken() external view returns(IERC20){
        return maximizerRewardToken;
    }

    function withdrawMaximizerReward(uint256 _pid, uint256 _amount) external onlyVaultHealer {
        maximizerRewardToken.safeIncreaseAllowance(address(vaultHealer), _amount); //the approval for the subsequent transfer
        vaultHealer.stratWithdraw(_pid, _amount);
    }

}