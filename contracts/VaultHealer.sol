// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./QuartzUniV2Zap.sol";
import "./VaultHealerGate.sol";
import "./VaultHealerBoostedPools.sol";

contract VaultHealer is VaultHealerGate, VaultHealerBoostedPools {

    QuartzUniV2Zap immutable public zap;

    constructor(QuartzUniV2Zap _zap, IVaultFeeManager _vaultFeeManager)
        ERC1155("")
        VaultHealerBase(msg.sender) 
        VaultHealerBoostedPools(msg.sender)
    {
        zap = _zap;
        vaultFeeManager = _vaultFeeManager;
    }

   function isApprovedForAll(address account, address operator) public view override returns (bool) {
        return super.isApprovedForAll(account, operator) || operator == address(zap);
   }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override(ERC1155Supply, VaultHealerBoostedPools) {
        ERC1155Supply._beforeTokenTransfer(operator, from, to, ids, amounts, data);     
        VaultHealerBoostedPools._beforeTokenTransfer(operator, from, to, ids, amounts, data);
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
