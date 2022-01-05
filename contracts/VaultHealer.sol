// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./VaultHealerBoostedPools.sol";
import "./Magnetite.sol";
import "./QuartzUniV2Zap.sol";

contract VaultHealer is VaultHealerBoostedPools {
    
    bytes32 public constant PATH_SETTER = keccak256("PATH_SETTER");

    Magnetite public magnetite;
    QuartzUniV2Zap public zap;

    constructor(VaultFee[] memory _earnFees, VaultFee memory _withdrawFee)
        VaultHealerBase(msg.sender) 
        VaultHealerBoostedPools(msg.sender)
        VaultHealerFees(msg.sender, _earnFees, _withdrawFee)
        VaultHealerPause(msg.sender)
    {
        magnetite = new Magnetite();
        zap = new QuartzUniV2Zap(this);
        _setupRole(PATH_SETTER, msg.sender);
    }
    
    function setPath(address router, address[] calldata path) external onlyRole(PATH_SETTER) {
        magnetite.overridePath(router, path);
    }

    function vaultLength() external view returns (uint256) {
        return _vaultInfo.length;
    }

    function owner() external view returns (address) {
        return getRoleMember(DEFAULT_ADMIN_ROLE, 0);
    }
    
    function vaultInfo(uint vid) external view returns (IERC20 want, IStrategy strat) {
        return (_vaultInfo[vid].want, _vaultInfo[vid].strat);
    }

    // View function to see staked Want tokens on frontend.

    function stakedWantTokens(uint256 _vid, address _user) external view returns (uint256) {
        uint256 _sharesTotal = totalSupply(_vid);
        if (_sharesTotal == 0) return 0;
        
        uint256 wantLockedTotal = _vaultInfo[_vid].strat.wantLockedTotal();
        
        return balanceOf(_user, _vid) * wantLockedTotal / _sharesTotal;
    }
    function settings() external view returns (VaultSettings memory) {
        uint vid = findVid(msg.sender);
        return _vaultInfo[vid].settings;
    }


}
