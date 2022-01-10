// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./VaultHealerFactory.sol";
import {Magnetite} from "./Magnetite.sol";
import "./QuartzUniV2Zap.sol";

contract VaultHealer is VaultHealerFactory {
    
    bytes32 public constant PATH_SETTER = keccak256("PATH_SETTER");

    Magnetite public magnetite;
    QuartzUniV2Zap public zap;

    constructor(address[] memory _earnFeeReceivers, uint16[] memory _earnFeeRates, address _withdrawFeeReceiver, uint16 _withdrawFeeRate)
        VaultHealerBase(msg.sender) 
        VaultHealerBoostedPools(msg.sender)
        VaultHealerFees(msg.sender, _earnFeeReceivers, _earnFeeRates, _withdrawFeeReceiver, _withdrawFeeRate)
        VaultHealerPause(msg.sender)
    {
        magnetite = new Magnetite();
        zap = new QuartzUniV2Zap(IVaultHealer(address(this)));
        _setupRole(PATH_SETTER, msg.sender);
    }
    
    function setPath(address router, IERC20[] calldata path) external onlyRole(PATH_SETTER) {
        magnetite.overridePath(router, path);
    }

    function vaultLength() external view returns (uint256) {
        return _vaultInfo.length;
    }

    function owner() external view returns (address) {
        return getRoleMember(DEFAULT_ADMIN_ROLE, 0);
    }
    
    function vaultInfo(uint vid) external view returns (IERC20 want, IStrategy _strat) {
        return (_vaultInfo[vid].want, strat(vid));
    }
    function rewardDebt(uint vid, address _user) external view returns (uint) {
        return _vaultInfo[vid].user[_user].rewardDebt;
    }

    // View function to see staked Want tokens on frontend.

    function stakedWantTokens(uint256 _vid, address _user) external view returns (uint256) {
        uint256 _sharesTotal = totalSupply(_vid);
        if (_sharesTotal == 0) return 0;
        
        uint256 wantLockedTotal = strat(_vid).wantLockedTotal();
        
        return balanceOf(_user, _vid) * wantLockedTotal / _sharesTotal;
    }
   function isApprovedForAll(address account, address operator) public view override returns (bool) {
        return super.isApprovedForAll(account, operator) || operator == address(zap);
   }
    
}
