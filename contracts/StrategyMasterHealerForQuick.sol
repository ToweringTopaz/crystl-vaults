// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./libs/IStakingRewards.sol";
import "./StrategyMasterHealer.sol";

contract StrategyMasterHealerForQuick is StrategyMasterHealer {
    using SafeERC20 for IERC20;
    
    constructor(
        address[5] memory _configAddress, //vaulthealer, masterchef, unirouter, want, earned
        uint256 _pid,
        uint256 _tolerance,
        address[] memory _earnedToWmaticPath,
        address[] memory _earnedToUsdcPath,
        address[] memory _earnedToCrystlPath,
        address[] memory _earnedToToken0Path,
        address[] memory _earnedToToken1Path
    ) StrategyMasterHealer(
        _configAddress,
        _pid,
        _tolerance, 
        _earnedToWmaticPath,
        _earnedToUsdcPath, 
        _earnedToCrystlPath,
        _earnedToToken0Path,
        _earnedToToken1Path
    ) { }

    function _vaultDeposit(uint256 _amount) internal override {
        IERC20(wantAddress).safeIncreaseAllowance(masterchefAddress, _amount);
        IStakingRewards(masterchefAddress).stake(_amount);
    }
    
    function _vaultWithdraw(uint256 _amount) internal override {
        IStakingRewards(masterchefAddress).withdraw(_amount);
    }
    
    function _vaultHarvest() internal override {
        IStakingRewards(masterchefAddress).getReward();
    }
    
    //I'm pretty confident this one below is right - it's the balance that the vault holds of shares in the farm
    function vaultSharesTotal() public override view returns (uint256) {
        uint256 amount = IStakingRewards(masterchefAddress).balanceOf(address(this));
        return amount;
    }
    // interestingly, you do get the reward with this exit function, 
    // which you don't with a Masterchef emergency withdraw
    function _emergencyVaultWithdraw() internal override {
        IStakingRewards(masterchefAddress).exit(); 
    }

}