// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./libs/IStakingRewards.sol";
import "./BaseStrategyLPSingle.sol";
import "./libs/IDragonLair.sol";

contract StrategyMasterHealerForQuickSwapdQuick is BaseStrategyLPSingle {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public masterchefAddress;
    uint256 public pid;
    address public constant dQuick = 0xf28164A485B0B2C90639E47b0f377b4a438a16B1;

    constructor(
        address[5] memory _configAddress, //vaulthealer, stakingRewards, unirouter, want, earned
        uint256 _pid,
        uint256 _tolerance,
        address[] memory _earnedToWmaticPath,
        address[] memory _earnedToUsdcPath,
        address[] memory _earnedToCrystlPath,
        address[] memory _earnedToToken0Path,
        address[] memory _earnedToToken1Path,
        address[] memory _token0ToEarnedPath,
        address[] memory _token1ToEarnedPath
    ) {
        govAddress = msg.sender;
        vaultChefAddress = _configAddress[0];
        masterchefAddress = _configAddress[1];
        uniRouterAddress = _configAddress[2];

        wantAddress = _configAddress[3];
        token0Address = IUniPair(wantAddress).token0();
        token1Address = IUniPair(wantAddress).token1();
        
        pid = _pid;
        earnedAddress = _configAddress[4];
        tolerance = _tolerance;

        earnedToWnativePath = _earnedToWmaticPath;
        earnedToUsdPath = _earnedToUsdcPath;
        earnedToCrystlPath = _earnedToCrystlPath;
        earnedToToken0Path = _earnedToToken0Path;
        earnedToToken1Path = _earnedToToken1Path;
        token0ToEarnedPath = _token0ToEarnedPath;
        token1ToEarnedPath = _token1ToEarnedPath;

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
        IDragonLair(dQuick).leave(IERC20(dQuick).balanceOf(address(this)));
    }
    
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

    function _emergencyVaultWithdraw() internal override {
        IStakingRewards(masterchefAddress).exit(); 
    }

    function _beforeDeposit(address _to) internal override {
        
    }

    function _beforeWithdraw(address _to) internal override {
        
    }
}