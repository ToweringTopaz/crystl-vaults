// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./QuartzUniV2Zap.sol";
import "./VaultHealerBoostedPools.sol";

contract VaultHealer is VaultHealerBoostedPools {

    QuartzUniV2Zap immutable public zap;

    constructor(address _owner, address _feeManager, address _zap)
        VaultHealerBase(_owner)
        VaultHealerBoostedPools(_owner)
    {
        magnetite = new Magnetite();
        zap = new QuartzUniV2Zap(address(this));
        vaultView = new VaultView(zap);
        vaultFeeManager = new VaultFeeManager(address(this), withdrawReceiver, withdrawRate, earnReceivers, earnRates);
        _setupRole(DEFAULT_ADMIN_ROLE, _owner);
        _setupRole(PATH_SETTER, _owner);

    }
    function isApprovedForAll(address account, address operator) public view override returns (bool) {
            return super.isApprovedForAll(account, operator) || operator == address(zap);
    }

    /* todo: remove this after updating tests
    function owner() external view returns (address) {
        return getRoleMember(DEFAULT_ADMIN_ROLE, 0);
    }
    */

}
