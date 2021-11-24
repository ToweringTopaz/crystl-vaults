// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./libs/IStakingRewards.sol";
import "./BaseStrategyLPDouble.sol";

contract StrategyMasterHealerForStakingMultiRewards is BaseStrategyLPDouble {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public masterchefAddress; //actually a StakingRewards contract in this case
    uint256 public pid;

    constructor(
        address[4] memory _configAddress, //vaulthealer, stakingRewards, unirouter, want, earned, earnedBeta
        uint256 _pid,
        uint256 _tolerance,
        address[] memory _earnedToWnativePath,
        address[] memory _earnedToUsdcPath,
        address[] memory _earnedToCrystlPath,
        address[] memory _earnedToToken0Path,
        address[] memory _earnedToToken1Path,
        address[] memory _token0ToEarnedPath,
        address[] memory _token1ToEarnedPath,
        address[] memory _earnedBetaToEarnedPath
    ) {
        vaultChefAddress = _configAddress[0];
        masterchefAddress = _configAddress[1];
        uniRouterAddress = _configAddress[2];

        wantAddress = _configAddress[3];
        token0Address = _token0ToEarnedPath[0];
        token1Address = _token1ToEarnedPath[0];

        wNativeAddress = _earnedToWnativePath[_earnedToWnativePath.length-1];

        pid = _pid;
        earnedAddress = _earnedToWnativePath[0];
        earnedBetaAddress = _earnedBetaToEarnedPath[0];
        tolerance = _tolerance;

        earnedToWnativePath = _earnedToWnativePath;
        earnedToUsdPath = _earnedToUsdcPath;
        earnedToCrystlPath = _earnedToCrystlPath;
        earnedToToken0Path = _earnedToToken0Path;
        earnedToToken1Path = _earnedToToken1Path;
        token0ToEarnedPath = _token0ToEarnedPath;
        token1ToEarnedPath = _token1ToEarnedPath;
        earnedBetaToEarnedPath = _earnedBetaToEarnedPath;

        transferOwnership(vaultChefAddress);
        
        _resetAllowances();
    }

    function _vaultDeposit(uint256 _amount) internal override {
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
    
    function wantLockedTotal() public override view returns (uint256) {
        return IERC20(wantAddress).balanceOf(address(this))
            .add(vaultSharesTotal());
    }

    function _resetAllowances() internal override {
        IERC20(wantAddress).safeApprove(masterchefAddress, uint256(0));
        IERC20(wantAddress).safeIncreaseAllowance(
            masterchefAddress,
            type(uint256).max
        );

        IERC20(earnedAddress).safeApprove(uniRouterAddress, uint256(0));
        IERC20(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            type(uint256).max
        );

        IERC20(earnedBetaAddress).safeApprove(uniRouterAddress, uint256(0));
        IERC20(earnedBetaAddress).safeIncreaseAllowance(
            uniRouterAddress,
            type(uint256).max
        );
        IERC20(token0Address).safeApprove(uniRouterAddress, uint256(0));
        IERC20(token0Address).safeIncreaseAllowance(
            uniRouterAddress,
            type(uint256).max
        );

        IERC20(token1Address).safeApprove(uniRouterAddress, uint256(0));
        IERC20(token1Address).safeIncreaseAllowance(
            uniRouterAddress,
            type(uint256).max
        );

    }
    // interestingly, you do get the reward with this exit function, 
    // which you don't with a Masterchef emergency withdraw
    function _emergencyVaultWithdraw() internal override {
        IStakingRewards(masterchefAddress).exit(); 
    }

    function _beforeDeposit(address _to) internal override {
        
    }

    function _beforeWithdraw(address _to) internal override {
        
    }
}