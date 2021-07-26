// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IMasterHealer.sol";
import "./BaseBaseStrategy.sol";


//A simple strategy to compound CRYSTL. It's built to be gas-efficient and unbreakable
contract CrystalCore is BaseBaseStrategy {
    using SafeERC20 for IERC20;

    IMasterHealer internal constant MASTER_HEALER = IMasterHealer(0xeBCC84D2A73f0c9E23066089C6C24F4629Ef1e6d);
    uint256 internal constant PID = 0;
    
    constructor (address _vaultHealerAddress)
        BaseBaseStrategy(CRYSTL, CRYSTL, _vaultHealerAddress) // those variables unused for this contract
    {
        transferOwnership(_vaultHealerAddress);
        
        //initialize allowance
        IERC20(CRYSTL).safeApprove(address(MASTER_HEALER), uint256(0));
        IERC20(CRYSTL).safeIncreaseAllowance(
            address(MASTER_HEALER),
            type(uint256).max
        );
        
        IERC20(CRYSTL).safeApprove(_vaultHealerAddress, uint256(0));
        IERC20(CRYSTL).safeIncreaseAllowance(
            address(_vaultHealerAddress),
            type(uint256).max
        );
    }
    
    function isCrystalCore() external override pure returns (bool) { return true; }
    
    function vaultTotal() public view override returns (uint256) {
        (uint256 amount,) = MASTER_HEALER.userInfo(PID, address(this));
        return amount;
    }
     
    function wantLockedTotal() public override view returns (uint256) {
        return IERC20(CRYSTL).balanceOf(address(this)) + vaultTotal();
    }
    
    function buyBack(uint256 _earnedAmt) internal override returns (uint256) {
        
        if (_earnedAmt == 0 || buybackRate == 0) return _earnedAmt;
        
        uint256 buybackAmt = _earnedAmt * buybackRate / BASIS_POINTS;

        IERC20(CRYSTL).safeTransfer(buybackReceiver, buybackAmt);
        
        return _earnedAmt - buybackAmt;
    }

    // Main want token compounding function
    function earn() external override whenNotPaused onlyOwner returns (uint256) {
        
        if (lastEarnBlock == block.number) return 0; // only compound once per block max
        
        // Harvest crystl
        MASTER_HEALER.withdraw(PID, 0);

        uint256 earnedAmt = IERC20(CRYSTL).balanceOf(address(this));
        if (earnedAmt == 0) return 0;

        // Pay buyback fee
        earnedAmt = buyBack(earnedAmt);

        lastEarnBlock = block.number;

        _farm();
        
        return 0;
    }
    function _vaultDeposit(uint256 _amount) internal override {
        MASTER_HEALER.deposit(PID, _amount);
    }
    
    function _vaultWithdraw(uint256 _amount) internal override {
        MASTER_HEALER.withdraw(PID, _amount);
    }
    
    function _resetAllowances() internal override {
        IERC20(CRYSTL).safeApprove(address(MASTER_HEALER), uint256(0));
        IERC20(CRYSTL).safeIncreaseAllowance(
            address(MASTER_HEALER),
            type(uint256).max
        );
        IERC20(CRYSTL).safeApprove(vaultHealerAddress, uint256(0));
        IERC20(CRYSTL).safeIncreaseAllowance(
            address(vaultHealerAddress),
            type(uint256).max
        );
    }
    
    function _emergencyVaultWithdraw() internal override {
        MASTER_HEALER.emergencyWithdraw(PID);
    }
}