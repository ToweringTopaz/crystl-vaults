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
import "./BaseStrategy.sol";

contract StrategyCrystallizer is BaseStrategy {
    using SafeERC20 for IERC20;
    using GibbonRouter for AmmData;
    
    IMasterHealer public immutable masterHealer;
    uint256 public immutable pid;
    
    constructor(
        AmmData _farmAMM,
        address _wantAddress,
        address _earnedAddress,
        address _vaultHealerAddress,
        address _masterHealerAddress,
        uint256 _pid,
        address[] memory _earnedToMaticPath
    ) BaseStrategy(_farmAMM, _wantAddress, _earnedAddress, _vaultHealerAddress) {
        
        masterHealer = IMasterHealer(_masterHealerAddress);
        pid = _pid;     // pid for the MasterHealer pool
        
        (address healerWantAddress,,,,) = IMasterHealer(_masterHealerAddress).poolInfo(_pid);
        require(healerWantAddress == _wantAddress, "Assigned pid doesn't match want token");

        require(
            _earnedToMaticPath[0] == _earnedAddress && _earnedToMaticPath[_earnedToMaticPath.length - 1] == WMATIC,
            "Tokens and paths mismatch"
        );

        earnedToMaticPath = _earnedToMaticPath;
        
        transferOwnership(_vaultHealerAddress);
        
        //initialize allowances
        IERC20(_wantAddress).safeApprove(_masterHealerAddress, uint256(0));
        IERC20(_wantAddress).safeIncreaseAllowance(
            address(_masterHealerAddress),
            type(uint256).max
        );
        IERC20(_wantAddress).safeApprove(_masterHealerAddress, uint256(0));
        IERC20(_wantAddress).safeIncreaseAllowance(
            address(_masterHealerAddress),
            type(uint256).max
        );
    }

    function isCrystallizer() external override pure returns (bool) { return true; }

    function _vaultDeposit(uint256 _amount) internal override {
        masterHealer.deposit(pid, _amount);
    }
    
    function _vaultWithdraw(uint256 _amount) internal override {
        masterHealer.withdraw(pid, _amount);
    }
    
    function _vaultHarvest() internal {
        masterHealer.withdraw(pid, 0);
    }
    
    function vaultSharesTotal() public override view returns (uint256) {
        (uint256 amount,) = masterHealer.userInfo(pid, address(this));
        return amount;
    }
     
    function wantLockedTotal() public override view returns (uint256) {
        return IERC20(wantAddress).balanceOf(address(this)) + vaultSharesTotal();
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
    
    function earn() external override whenNotPaused onlyOwner returns (uint256 crystlHarvest) {
        
        if (lastEarnBlock == block.number) return 0; // only compound once per block max
        lastEarnBlock = block.number;
        
        // Harvest farm tokens
        _vaultHarvest();

        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));
        if (earnedAmt == 0) return 0;
          
        //convert earned to crystl, if necessary
        if (earnedAddress != CRYSTL) {
            
            uint wmaticAmt = farmAMM.swap(
                earnedAmt,
                earnedToMaticPath,
                address(this)
            );
        
            earnedAmt = APESWAP.swap(
                wmaticAmt,
                WMATIC,
                CRYSTL,
                address(this)
            );
        } else earnedAmt = IERC20(CRYSTL).balanceOf(address(this));

        earnedAmt = buyBack(earnedAmt);
        IERC20(CRYSTL).safeTransfer(vaultHealerAddress, earnedAmt);
        
        return earnedAmt;
    }
    
}