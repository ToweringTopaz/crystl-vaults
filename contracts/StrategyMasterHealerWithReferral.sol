// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./libs/IMasterchefWithReferral.sol";
import "./BaseStrategyLPSingle.sol";

contract StrategyMasterHealerWithReferral is BaseStrategyLPSingle {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public masterchefAddress;
    uint256 public pid;

    constructor(
        address[7] memory _configAddress, //vaulthealer, masterchef, unirouter, want, earned
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
        vaultChefAddress = _configAddress[0];
        masterchefAddress = _configAddress[1];
        uniRouterAddress = _configAddress[2];

        wantAddress = _configAddress[3];
        token0Address = _token0ToEarnedPath[0];
        token1Address = _token1ToEarnedPath[0];

        rewardAddress = _configAddress[4];
        withdrawFeeAddress = _configAddress[4];
        buyBackAddress = _configAddress[5];

        crystlAddress = _configAddress[6];
        wNativeAddress = _earnedToWmaticPath[1];

        pid = _pid;
        earnedAddress = _earnedToWmaticPath[0];
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
        IMasterchefWithReferral(masterchefAddress).deposit(pid, _amount, address(0));
    }
    
    function _vaultWithdraw(uint256 _amount) internal override {
        IMasterchefWithReferral(masterchefAddress).withdraw(pid, _amount);
    }
    
    function _vaultHarvest() internal override {
        IMasterchefWithReferral(masterchefAddress).withdraw(pid, 0);
    }
    
    function vaultSharesTotal() public override view returns (uint256) {
        (uint256 amount,) = IMasterchefWithReferral(masterchefAddress).userInfo(pid, address(this));
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
        IMasterchefWithReferral(masterchefAddress).emergencyWithdraw(pid);
    }

    function _beforeDeposit(address _to) internal override {
        
    }

    function _beforeWithdraw(address _to) internal override {
        
    }
}