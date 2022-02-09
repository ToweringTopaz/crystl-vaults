// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IMagnetite.sol";
import "./IStrategy.sol";

interface IVaultHealer {

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
    function vaultInfo(uint vid) external view returns (
        IERC20 want,
        uint32 lastEarnBlock,
        uint32 numMaximizers, //number of maximizer vaults pointing here. If this is vid 0x00000045, its first maximizer will be 0x0000004500000000
        uint112 wantLockedLastUpdate,
        uint112 totalMaximizerEarningsOffset,
        uint32 numBoosts,
        uint256 panicLockExpiry //no gas savings from packing this variable
    );
}