// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IMagnetite.sol";
import "./IStrategy.sol";
import "./IVaultFeeManager.sol";
import "@openzeppelin/contracts/access/IAccessControlEnumerable.sol";

interface IVaultHealer is IAccessControlEnumerable {

    event AddVault(uint indexed vid);
    event SetVaultFeeManager(IVaultFeeManager indexed _manager);
    event Paused(uint indexed vid);
    event Unpaused(uint indexed vid);
    event Deposit(address indexed from, address indexed to, uint256 indexed vid, uint256 amount);
    event Withdraw(address indexed from, address indexed to, uint256 indexed vid, uint256 amount);
    event Earned(uint256 indexed vid, uint256 wantAmountEarned);
    event AddBoost(uint indexed boostid);
    event EnableBoost(address indexed user, uint indexed boostid);
    event BoostEmergencyWithdraw(address user, uint _boostID);
    event SetAutoEarn(uint indexed vid, bool earnBeforeDeposit, bool earnBeforeWithdraw);
    //function vaultInfo(uint vid) external view returns (IERC20 want, IStrategy _strat);
    //function stratDeposit(uint256 _vid, uint256 _wantAmt) external;
    //function stratWithdraw(uint256 _vid, uint256 _wantAmt) external;
    function executePendingDeposit(address _to, uint112 _amount) external;
    //function findVid(address) external view returns (uint32);
    function withdrawFrom(uint256 _vid, uint256 _wantAmt, address _from, address _to) external;
    function withdraw(uint256 _vid, uint256 _wantAmt) external;
    function deposit(uint256 _vid, uint256 _wantAmt, address _to) external;
    function deposit(uint256 _vid, uint256 _wantAmt) external;
    function strat(uint256 _vid) external view returns (IStrategy);

    struct VaultInfo {
        IERC20 want;
        uint8 noAutoEarn;
        bool active; //not paused
        uint32 lastEarnBlock;
        uint16 numBoosts;
        uint32 numMaximizers; //number of maximizer vaults pointing here. For vid 0x00000045, its maximizer will be 0x000000450000000, 0x000000450000001, ...
        
        uint256 panicLockExpiry; //no gas savings from packing this variable
    }

    function vaultInfo(uint vid) external view returns (IERC20, uint8, bool, uint32,uint16,uint32,uint256);
    function nextVid() external view returns (uint32);
}