// SPDX-License-Identifier: MIT

/*
Join us at PolyCrystal.Finance!
█▀▀█ █▀▀█ █░░ █░░█ █▀▀ █▀▀█ █░░█ █▀▀ ▀▀█▀▀ █▀▀█ █░░ 
█░░█ █░░█ █░░ █▄▄█ █░░ █▄▄▀ █▄▄█ ▀▀█ ░░█░░ █▄▄█ █░░ 
█▀▀▀ ▀▀▀▀ ▀▀▀ ▄▄▄█ ▀▀▀ ▀░▀▀ ▄▄▄█ ▀▀▀ ░░▀░░ ▀░░▀ ▀▀▀
*/

pragma solidity 0.6.12;

import "./interfaces/IMasterHealer.sol";

import "./BaseStrategyApeLPSingle.sol";

contract StrategyMasterHealer is BaseStrategyApeLPSingle {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IMasterHealer public masterHealer;
    uint256 public pid;

    constructor(
        address _vaultHealerAddress,
        address _masterHealerAddress,
        uint256 _pid,
        address _wantAddress,
        address _earnedAddress,
        address[] memory _earnedToCrystlPath,
        address[] memory _earnedToToken0Path,
        address[] memory _earnedToToken1Path,
        address[] memory _token0ToEarnedPath,
        address[] memory _token1ToEarnedPath
    ) public {
        govAddress = msg.sender;
        vaultHealerAddress = _vaultHealerAddress;
        masterHealer = IMasterHealer(_masterHealerAddress);

        (address healerWantAddress,,,,) = masterHealer.poolInfo(_pid);
        require(healerWantAddress == _wantAddress, "Assigned pid doesn't match want token");
        
        pid = _pid;                     // pid for the MasterHealer pool
        wantAddress = _wantAddress;
        
        token0Address = IApePair(wantAddress).token0();
        token1Address = IApePair(wantAddress).token1();

        require(
            _earnedToCrystlPath[0] == _earnedAddress && _earnedToCrystlPath[_earnedToCrystlPath.length - 1] == crystlAddress 
            && _token0ToEarnedPath[0] == token0Address && _token0ToEarnedPath[_token0ToEarnedPath.length - 1] == _earnedAddress
            && _token1ToEarnedPath[0] == token1Address && _token1ToEarnedPath[_token1ToEarnedPath.length - 1] == _earnedAddress
            && _earnedToToken0Path[0] == _earnedAddress && _earnedToToken0Path[_earnedToToken0Path.length - 1] == token0Address
            && _earnedToToken1Path[0] == _earnedAddress && _earnedToToken1Path[_earnedToToken1Path.length - 1] == token1Address,
            "Tokens and paths mismatch");

        earnedAddress = _earnedAddress;
        earnedToCrystlPath = _earnedToCrystlPath;
        earnedToToken0Path = _earnedToToken0Path;
        earnedToToken1Path = _earnedToToken1Path;
        token0ToEarnedPath = _token0ToEarnedPath;
        token1ToEarnedPath = _token1ToEarnedPath;
        
        transferOwnership(vaultHealerAddress);
        
        _resetAllowances();
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
    
    function vaultSharesTotal() public override view returns (uint256) {
        (uint256 amount,) = masterHealer.userInfo(pid, address(this));
        return amount;
    }
     
    function wantLockedTotal() public override view returns (uint256) {
        return IERC20(wantAddress).balanceOf(address(this))
            .add(vaultSharesTotal());
    }

    function _resetAllowances() internal override {
        IERC20(wantAddress).safeApprove(address(masterHealer), uint256(0));
        IERC20(wantAddress).safeIncreaseAllowance(
            address(masterHealer),
            uint256(-1)
        );
    }
    
    function _emergencyVaultWithdraw() internal override {
        masterHealer.emergencyWithdraw(pid);
    }
}
