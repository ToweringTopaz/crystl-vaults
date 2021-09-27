// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./libs/IMasterchef.sol";
import "./BaseStrategyLPSingle.sol";

contract StrategyMasterHealer is BaseStrategyLPSingle {
    using SafeERC20 for IERC20;

    address immutable public masterchefAddress;
    uint256 immutable public pid;

    constructor(
        address[5] memory _configAddress, //vaulthealer, masterchef, unirouter, want, earned
        uint256 _pid,
        uint256 _tolerance,
        address[][5] memory _earnedPaths  //wmatic, usdc, crystl, token0, token1
    ) BaseStrategy(_configAddress[0], _configAddress[2], _configAddress[3], _configAddress[4], _tolerance, _earnedPaths[0], _earnedPaths[1], _earnedPaths[2]) {

        masterchefAddress = _configAddress[1];
        
        address _wantAddress = _configAddress[3];
        token0Address = IUniPair(_wantAddress).token0();
        token1Address = IUniPair(_wantAddress).token1();

        pid = _pid;

        earnedToToken0Path = _earnedPaths[3];
        earnedToToken1Path = _earnedPaths[4];
        
        address _unirouter = _configAddress[2];
        
        //initialize allowances for token0/token1
        setMaxAllowance(token0Address, _unirouter);
        setMaxAllowance(token1Address, _unirouter);
    }

    function _vaultDeposit(uint256 _amount) internal virtual override {
        IERC20(wantAddress).safeIncreaseAllowance(masterchefAddress, _amount);
        IMasterchef(masterchefAddress).deposit(pid, _amount);
    }
    
    function _vaultWithdraw(uint256 _amount) internal virtual override {
        IMasterchef(masterchefAddress).withdraw(pid, _amount);
    }
    
    function _vaultHarvest() internal virtual override {
        IMasterchef(masterchefAddress).withdraw(pid, 0);
    }
    
    function vaultSharesTotal() public virtual override view returns (uint256) {
        (uint256 amount,) = IMasterchef(masterchefAddress).userInfo(pid, address(this));
        return amount;
    }
    
    function _resetAllowances() internal override {
        IERC20(wantAddress).safeApprove(masterchefAddress, 0);

        setMaxAllowance(earnedAddress,uniRouterAddress);
        setMaxAllowance(token0Address,uniRouterAddress);
        setMaxAllowance(token1Address,uniRouterAddress);

    }
    
    function _emergencyVaultWithdraw() internal virtual override {
        IMasterchef(masterchefAddress).emergencyWithdraw(pid);
    }
}