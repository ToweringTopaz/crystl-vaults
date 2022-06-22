// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "./Strategy.sol";
import "./interfaces/IxArgo.sol";

contract StrategyArgo is Strategy {
    using StrategyConfig for StrategyConfig.MemPointer;

    IxArgo public constant xArgo = IxArgo(0xb966B5D6A0fCd5b373B180Bbe072BBFbbEe10552);
    
    constructor(IVaultHealer _vaultHealer) Strategy(_vaultHealer) {}

    function _vaultHarvest() internal override {
        super._vaultHarvest();
        (bool success,) = xArgo.argoStaking().call(abi.encodeWithSelector(0x4663d049, xArgo.balanceOf(address(this))));
        if(!success){
            revert("Could Not unstake xArgo!");
        }

    }
        
}