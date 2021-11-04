// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./libs/IMasterchef.sol";
import "./BaseStrategyLPSingle.sol";

contract StrategyMasterHealerForDoubleReflect is BaseStrategyLPSingle {
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

        slippageFactor = 800;

        transferOwnership(vaultChefAddress);
        
        _resetAllowances();
    }

    function _vaultDeposit(uint256 _amount) internal override {
        IMasterchef(masterchefAddress).deposit(pid, _amount);
    }
    
    function _vaultWithdraw(uint256 _amount) internal override {
        IMasterchef(masterchefAddress).withdraw(pid, _amount);
    }
    
    function _vaultHarvest() internal override {
        IMasterchef(masterchefAddress).withdraw(pid, 0);
    }
    
    function vaultSharesTotal() public override view returns (uint256) {
        (uint256 amount,) = IMasterchef(masterchefAddress).userInfo(pid, address(this));
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
        IMasterchef(masterchefAddress).emergencyWithdraw(pid);
    }

    function _beforeDeposit(address _to) internal override {
        
    }

    function _beforeWithdraw(address _to) internal override {
        
    }

    function _safeSwap(
        uint256 _amountIn,
        address[] memory _path,
        address _to
        ) internal override {
            uint256[] memory amounts = IUniRouter02(uniRouterAddress).getAmountsOut(_amountIn, _path);
            uint256 amountOut = amounts[amounts.length.sub(1)];

        if (_path[_path.length.sub(1)] == crystlAddress && _to == buyBackAddress) {
            burnedAmount = burnedAmount.add(amountOut);
        }

        IUniRouter02(uniRouterAddress).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amountIn,
            amountOut.mul(slippageFactor).div(1000),
            _path,
            _to,
            block.timestamp.add(600)
        );
    }

    function _safeSwapWnative(
        uint256 _amountIn,
        address[] memory _path,
        address _to
        ) internal override {
        uint256[] memory amounts = IUniRouter02(uniRouterAddress).getAmountsOut(_amountIn, _path);
        uint256 amountOut = amounts[amounts.length.sub(1)];

        IUniRouter02(uniRouterAddress).swapExactTokensForETHSupportingFeeOnTransferTokens(
            _amountIn,
            amountOut.mul(slippageFactor).div(1000),
            _path,
            _to,
            block.timestamp.add(600)
        );
    }
}