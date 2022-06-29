// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "./Strategy.sol";
import "./interfaces/ISaharaDaoStaking.sol";

contract StrategyCustomRouter is Strategy {
    using StrategyConfig for StrategyConfig.MemPointer;
    using SafeERC20 for IERC20;

    function safeSwap(
        uint256 _amountIn,
        IERC20[] memory path
    ) internal override {
        IUniRouter _router = config.router();

        path[0].safeIncreaseAllowance(address(_router), _amountIn);
        
        if (config.feeOnTransfer()) {
            uint amountOutMin = _router.getAmountsOut(_amountIn, path)[path.length - 2] * config.slippageFactor() / 256;
            _router.swapExactTokensForTokensSupportingFeeOnTransferTokens(_amountIn, amountOutMin, path, address(this), block.timestamp);
        } else {
            _router.swapExactTokensForTokens(_amountIn, 0, path, address(this), block.timestamp)[path.length - 2];
        }
    }
}