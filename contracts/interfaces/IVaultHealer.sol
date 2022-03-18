// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IStrategy.sol";
import "./IVaultFeeManager.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

interface IVaultHealer {

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
    event FailedEarn(uint vid, string reason);
    event FailedEarnBytes(uint vid, bytes reason);
    event FailedWithdrawFee(uint vid, string reason);
    event FailedWithdrawFeeBytes(uint vid, bytes reason);
    event MaximizerHarvest(address indexed account, uint indexed vid, uint targetShares);
	
	error PausedError(uint256 vid); //Action cannot be completed on a paused vid
	error MaximizerTooDeep(uint256 targetVid); //Too many layers of nested maximizers (13 is plenty I should hope)
	error VidOutOfRange(uint256 vid); //Specified vid does not represent an existing vault
	error PanicCooldown(uint256 expiry); //Cannot panic this vault again until specified time
	error InvalidFallback(); //The fallback function should not be called in this context
	error WithdrawZeroBalance(address from); //User attempting to withdraw from a vault when they have zero shares
	error UnauthorizedPendingDepositAmount(); //Strategy attempting to pull more tokens from the user than authorized
    error RestrictedFunction(bytes4 selector);

	error NotApprovedToEnableBoost(address account, address operator);
	error BoostPoolNotActive(uint256 _boostID);
	error BoostPoolAlreadyJoined(address account, uint256 _boostID);
	error BoostPoolNotJoined(address account, uint256 _boostID);
    error ArrayMismatch(uint lenA, uint lenB);

	error ERC1167_Create2Failed();	//Low-level error with creating a strategy proxy
	error ERC1167_ImplZeroAddress(); //If attempting to deploy a strategy with a zero implementation address
	
    function executePendingDeposit(address _to, uint192 _amount) external;

    function withdraw(uint256 _vid, uint256 _wantAmt, address _from, address _to, bytes calldata _data) external;
    function withdraw(uint256 _vid, uint256 _wantAmt, bytes calldata _data) external;
    function deposit(uint256 _vid, uint256 _wantAmt, address _to, bytes calldata _data) external payable;
    function deposit(uint256 _vid, uint256 _wantAmt, bytes calldata _data) external payable;

    function strat(uint256 _vid) external view returns (IStrategy);
    function maximizerDeposit(uint256 _vid, uint256 _wantAmt, bytes calldata _data) external payable;
    struct VaultInfo {
        IERC20 want;
        uint8 noAutoEarn;
        bool active; //not paused
        uint48 lastEarnBlock;
        uint16 numBoosts;
        uint16 numMaximizers; //number of maximizer vaults pointing here. For vid 0x00000045, its maximizer will be 0x000000450000000, 0x000000450000001, ...
    }

    function vaultInfo(uint vid) external view returns (IERC20, uint8, bool, uint48,uint16,uint16);
    function numVaultsBase() external view returns (uint16);
    function vhAuth() external view returns (IAccessControl);
}