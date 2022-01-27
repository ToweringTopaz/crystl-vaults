// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./libs/IStrategy.sol";
import "./libs/Tactics.sol";
import "./libs/Vault.sol";
import "./FirewallProxyImplementation.sol";
import {IERC20Upgradeable as IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

abstract contract BaseStrategy is FirewallProxyImplementation, IStrategy {
    using SafeERC20 for IERC20;

    struct Settings {
        Tactics.TacticsA tacticsA;
        Tactics.TacticsB tacticsB;
        IERC20 wantToken; //The token which is deposited and earns a yield
        uint256 slippageFactor; //(16) sets a limit on losses due to deposit fee in pool, reflect fees, rounding errors, etc.
        uint256 feeOnTransfer; //(8) 0 = false; 1 = true
        uint256 dust; //(96) min token amount to swap/deposit. Prevents token waste, exploits and unnecessary reverts
        uint256 targetVid; //(32)
        IUniRouter router; //UniswapV2 compatible router
        IMagnetite magnetite;
        IERC20[2] lpToken;
        IERC20[4] earned;
    }

    function vaultSharesTotal() external view returns (uint256) {
        return _vaultSharesTotal(getSettings());
    }
    function _vaultSharesTotal(Settings memory s) internal view returns (uint256) {
        return Tactics.vaultSharesTotal(s.tacticsA);
    }
    function _vaultDeposit(Settings memory s, uint256 _amount) internal {   
        //token allowance for the pool to pull the correct amount of funds only
        s.wantToken.safeIncreaseAllowance(address(uint160(Tactics.TacticsA.unwrap(s.tacticsA) >> 96)), _amount); //address(s.tacticsA >> 96) is masterchef        
        Tactics.deposit(s.tacticsA, s.tacticsB, _amount);
    }
    function _farm(Settings memory s) internal virtual;
    
    function wantLockedTotal() external virtual view returns (uint256) {
        Settings memory s = getSettings();
        return s.wantToken.balanceOf(address(this)) + _vaultSharesTotal(s);
    }

    function panic() external {
        Settings memory s = getSettings();
        Tactics.emergencyVaultWithdraw(s.tacticsA, s.tacticsB);
    }
    function unpanic() external { 
        Settings memory s = getSettings();
        _farm(s);
    }
    function router() external view returns (IUniRouter) {
        Settings memory s = getSettings();
        return s.router;
    }
    function wantToken() external view returns (IERC20) {
        Settings memory s = getSettings();
        return s.wantToken;
    }
    function targetVid() external view returns (uint256) {
        Settings memory s = getSettings();
        return s.targetVid;
    }

    function getSettings() public view returns (Settings memory settings) {
        bytes memory data = getProxyData();
        assembly {
            settings := data
        }
    }
}