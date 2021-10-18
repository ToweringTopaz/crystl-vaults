// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IVaultHealer.sol";

library V2TotalBurned {
    
    function getTotalBurned(address vaultHealer) external view returns (uint total) {
        uint poolLength = IVaultHealer(vaultHealer).poolLength();
        
        for (uint i; i < poolLength; i++) {
            (,IStrategy strat) = IVaultHealer(vaultHealer).poolInfo(i);
            try strat.burnedAmount() returns (uint amt) {
                total += amt;
            }
            catch {}
        }
    }
}
