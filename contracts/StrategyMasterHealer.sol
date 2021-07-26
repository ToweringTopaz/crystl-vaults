// SPDX-License-Identifier: MIT

/*
Join us at PolyCrystal.Finance!
█▀▀█ █▀▀█ █░░ █░░█ █▀▀ █▀▀█ █░░█ █▀▀ ▀▀█▀▀ █▀▀█ █░░ 
█░░█ █░░█ █░░ █▄▄█ █░░ █▄▄▀ █▄▄█ ▀▀█ ░░█░░ █▄▄█ █░░ 
█▀▀▀ ▀▀▀▀ ▀▀▀ ▄▄▄█ ▀▀▀ ▀░▀▀ ▄▄▄█ ▀▀▀ ░░▀░░ ▀░░▀ ▀▀▀
*/

pragma solidity ^0.8.6;

import "./interfaces/IMasterHealer.sol";
import "@uniswap/v2-core@1.0.1/contracts/interfaces/IUniswapV2Pair.sol";
import "./BaseStrategyApeLPSingle.sol";

contract StrategyMasterHealer is BaseStrategyApeLPSingle {
    using SafeERC20 for IERC20;

    IMasterHealer public immutable masterHealer;
    uint256 public immutable pid;

    constructor(
        AmmData _farmAMM,
        address _vaultHealerAddress,
        address _masterHealerAddress,
        uint256 _pid,
        address _earnedAddress,
        address _wantAddress,
        address[] memory _earnedToMaticPath,
        address[] memory _earnedToToken0Path,
        address[] memory _earnedToToken1Path,
        address[] memory _token0ToEarnedPath,
        address[] memory _token1ToEarnedPath
    ) BaseStrategyApeLPSingle(_farmAMM, _wantAddress, _earnedAddress, _vaultHealerAddress) {
        
        masterHealer = IMasterHealer(_masterHealerAddress);
        pid = _pid;     // pid for the MasterHealer pool
        
        (address healerWantAddress,,,,) = IMasterHealer(_masterHealerAddress).poolInfo(_pid);
        require(healerWantAddress == _wantAddress, "Assigned pid doesn't match want token");
        
        address _token0Address = IUniswapV2Pair(_wantAddress).token0();
        address _token1Address = IUniswapV2Pair(_wantAddress).token1();

        require(
            _earnedToMaticPath[0] == _earnedAddress && _earnedToMaticPath[_earnedToMaticPath.length - 1] == WMATIC
            && _token0ToEarnedPath[0] == _token0Address && _token0ToEarnedPath[_token0ToEarnedPath.length - 1] == _earnedAddress
            && _token1ToEarnedPath[0] == _token1Address && _token1ToEarnedPath[_token1ToEarnedPath.length - 1] == _earnedAddress
            && _earnedToToken0Path[0] == _earnedAddress && _earnedToToken0Path[_earnedToToken0Path.length - 1] == _token0Address
            && _earnedToToken1Path[0] == _earnedAddress && _earnedToToken1Path[_earnedToToken1Path.length - 1] == _token1Address,
            "Tokens and paths mismatch"
        );

        earnedToMaticPath = _earnedToMaticPath;
        earnedToToken0Path = _earnedToToken0Path;
        earnedToToken1Path = _earnedToToken1Path;
        token0ToEarnedPath = _token0ToEarnedPath;
        token1ToEarnedPath = _token1ToEarnedPath;
        
        transferOwnership(_vaultHealerAddress);
        
        //initialize allowance
        IERC20(_wantAddress).safeApprove(_masterHealerAddress, uint256(0));
        IERC20(_wantAddress).safeIncreaseAllowance(
            address(_masterHealerAddress),
            type(uint256).max
        );
    }

    function _vaultDeposit(uint256 _amount) internal override {
        masterHealer.deposit(pid, _amount);
    }
    
    function _vaultWithdraw(uint256 _amount) internal override {
        masterHealer.withdraw(pid, _amount);
    }
    
    function _vaultHarvest() internal override {
        masterHealer.withdraw(pid, 0);
    }
    
    function vaultTotal() public override view returns (uint256) {
        (uint256 amount,) = masterHealer.userInfo(pid, address(this));
        return amount;
    }
     
    function wantLockedTotal() public override view returns (uint256) {
        return IERC20(wantAddress).balanceOf(address(this)) + vaultTotal();
    }

    function _resetAllowances() internal override {
        IERC20(wantAddress).safeApprove(address(masterHealer), uint256(0));
        IERC20(wantAddress).safeIncreaseAllowance(
            address(masterHealer),
            type(uint256).max
        );
    }
    
    function _emergencyVaultWithdraw() internal override {
        masterHealer.emergencyWithdraw(pid);
    }
}