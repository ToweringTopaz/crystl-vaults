// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./QuartzUniV2Zap.sol";
import "./VaultHealerBoostedPools.sol";

contract VaultHealer is VaultHealerBoostedPools {

    IMagnetite internal magnetite;
    QuartzUniV2Zap immutable public zap;

    constructor(address withdrawReceiver, uint16 withdrawRate, address[3] memory earnReceivers, uint16[3] memory earnRates)
        VaultHealerBase(msg.sender) 
        VaultHealerBoostedPools(msg.sender)
    {
        magnetite = new Magnetite();
        zap = new QuartzUniV2Zap(address(this));
        vaultView = new VaultView(zap);
        vaultFeeManager = new VaultFeeManager(address(this), withdrawReceiver, withdrawRate, earnReceivers, earnRates);
        _setupRole(PATH_SETTER, msg.sender);

    }
   function isApprovedForAll(address account, address operator) public view override returns (bool) {
        return super.isApprovedForAll(account, operator) || operator == address(zap);
   }

    function owner() external view returns (address) {
        return getRoleMember(DEFAULT_ADMIN_ROLE, 0);
    }
    function vaultInfo(uint vid) external view returns (IERC20 want, IStrategy _strat) {
        return (_vaultInfo[vid].want, strat(vid));
    }
    
    // View function to see staked Want tokens on frontend.
    function stakedWantTokens(uint256 _vid, address _user) external view returns (uint256) {
        uint256 _sharesTotal = totalSupply(_vid);
        if (_sharesTotal == 0) return 0;
        
        uint256 wantLockedTotal = strat(_vid).wantLockedTotal();
        
        return balanceOf(_user, _vid) * wantLockedTotal / _sharesTotal;
    }

}
