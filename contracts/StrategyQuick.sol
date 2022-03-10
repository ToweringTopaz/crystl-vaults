// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./Strategy.sol";
import "./interfaces/IDragonLair.sol";

contract StrategyQuick is Strategy {
    using StrategyConfig for StrategyConfig.MemPointer;

    IDragonLair public constant D_QUICK = IDragonLair(0xf28164A485B0B2C90639E47b0f377b4a438a16B1);

    constructor(address _vaultHealer) Strategy(_vaultHealer) {}

    function _vaultHarvest(IERC20 _wantToken) internal override {
        super._vaultHarvest(_wantToken);
        D_QUICK.leave(D_QUICK.balanceOf(address(this)));
    }
}