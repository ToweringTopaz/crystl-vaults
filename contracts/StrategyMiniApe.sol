// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./libs/IMiniChefV2.sol";
import "./BaseStrategyLPDouble.sol";

contract StrategyMiniApe is BaseStrategyLPDouble {
    using SafeERC20 for IERC20;

    address public miniapeAddress;
    uint256 public pid;
    
    constructor(
        address[6] memory _configAddress, //vaulthealer, miniape, unirouter, want, earned, earned2
        uint256 _pid,
        uint256 _tolerance,
        address[][5] memory _earnedPaths,  //wmatic, usdc, crystl, token0, token1
        address[][5] memory _earned2Paths
    ) BaseStrategy(_configAddress[0], _configAddress[2], _configAddress[3], _configAddress[4], _tolerance, _earnedPaths[0], _earnedPaths[1], _earnedPaths[2]) {

        miniapeAddress = _configAddress[1];
        
        address _wantAddress = _configAddress[3];
        token0Address = IUniPair(_wantAddress).token0();
        token1Address = IUniPair(_wantAddress).token1();

        pid = _pid;

        earnedToToken0Path = _earnedPaths[3];
        earnedToToken1Path = _earnedPaths[4];

        earned2ToWnativePath = _earned2Paths[0];
        earned2ToUsdPath = _earned2Paths[1];
        earned2ToCrystlPath = _earned2Paths[2];
        earned2ToToken0Path = _earned2Paths[3];
        earned2ToToken1Path = _earned2Paths[4];
        
        address _earnedAddress = _configAddress[4];
        earned2Address = _configAddress[5];
        
        address _unirouter = _configAddress[2];
        
        //initialize allowances for token0/token1
        IERC20(token0Address).safeIncreaseAllowance(_unirouter, type(uint256).max);
        IERC20(token1Address).safeIncreaseAllowance(_unirouter, type(uint256).max);
        IERC20(_earnedAddress).safeIncreaseAllowance(_unirouter, type(uint256).max);
        IERC20(earned2Address).safeIncreaseAllowance(_unirouter, type(uint256).max);
        
    }

    function _vaultDeposit(uint256 _amount) internal virtual override {
        IERC20(wantAddress).safeIncreaseAllowance(miniapeAddress, _amount);
        IMiniChefV2(miniapeAddress).deposit(pid, _amount, address(this));
    }
    
    function _vaultWithdraw(uint256 _amount) internal override {
        IMiniChefV2(miniapeAddress).withdraw(pid, _amount, address(this));
    }
    
    function _vaultHarvest() internal override {
        IMiniChefV2(miniapeAddress).harvest(pid, address(this));
    }

    function _resetAllowances() internal override {
        IERC20(wantAddress).safeApprove(miniapeAddress, 0);

        IERC20(earnedAddress).safeApprove(uniRouterAddress, 0);

        IERC20(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            type(uint256).max
        );
        

        IERC20(earned2Address).safeApprove(uniRouterAddress, 0);
        IERC20(earned2Address).safeIncreaseAllowance(
            uniRouterAddress,
            type(uint256).max
        );


        IERC20(token0Address).safeApprove(uniRouterAddress, 0);
        IERC20(token0Address).safeIncreaseAllowance(
            uniRouterAddress,
            type(uint256).max
        );


        IERC20(token1Address).safeApprove(uniRouterAddress, 0);

        IERC20(token1Address).safeIncreaseAllowance(
            uniRouterAddress,
            type(uint256).max
        );

    }

    function vaultSharesTotal() public override view returns (uint256) {
        (uint256 amount,) = IMiniChefV2(miniapeAddress).userInfo(pid, address(this));
        return amount;
    }
    
    function _emergencyVaultWithdraw() internal override {
        IMiniChefV2(miniapeAddress).emergencyWithdraw(pid, address(this));

    }
}
