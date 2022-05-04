// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import "./StrategyQuick.sol";
import "./BoostPool.sol";
import "./VaultHealer.sol";
import "./VaultHealerAuth.sol";

contract VaultDeploy {

    VaultHealer public immutable vaultHealer;
    Strategy public immutable strategy;
    StrategyQuick public immutable strategyQuick;
    BoostPool immutable public boostPoolImpl;

    constructor() {
        vaultHealer = VaultHealer(msg.sender);

        strategy = new Strategy(vaultHealer);
        strategyQuick = block.chainid == 137 ? new StrategyQuick(vaultHealer) : StrategyQuick(payable(0));
        boostPoolImpl = new BoostPool(address(vaultHealer));
    }
    
    function vhAuth() external view returns (address) { return address(vaultHealer.vhAuth()); }
    function zap() external view returns (address) { return address(vaultHealer.zap()); }
    function vaultFeeManager() external view returns (address) { return address(vaultHealer.vaultFeeManager()); }


}