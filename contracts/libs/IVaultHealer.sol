// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IERC20Upgradeable as IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./IMagnetite.sol";
import "./IStrategy.sol";

interface IVaultHealerMain {

    //function vaultInfo(uint vid) external view returns (IERC20 want, IStrategy _strat);
    //function stratDeposit(uint256 _vid, uint256 _wantAmt) external;
    //function stratWithdraw(uint256 _vid, uint256 _wantAmt) external;
    function executePendingDeposit(address _to, uint112 _amount) external;
    //function findVid(address) external view returns (uint32);
    function withdrawFrom(uint256 _vid, uint256 _wantAmt, address _from, address _to) external;
    function withdraw(uint256 _vid, uint256 _wantAmt) external;
    function deposit(uint256 _vid, uint256 _wantAmt, address _to) external;
    function deposit(uint256 _vid, uint256 _wantAmt) external;

}
interface IVaultView {
    function vaultInfo(uint vid) external view returns (IERC20 want, IStrategy _strat);
    function strat(uint256 _vid) external view returns (IStrategy);
    function magnetite() external view returns (IMagnetite);
}
interface IVaultHealer is IVaultHealerMain, IVaultView {}