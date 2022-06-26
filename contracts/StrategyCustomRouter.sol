// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "./Strategy.sol";
import "./interfaces/ISaharaDaoStaking.sol";

contract StrategyCustomRouter is Strategy {
    using StrategyConfig for StrategyConfig.MemPointer;
    using SafeERC20 for IERC20;

    constructor(IVaultHealer _vaultHealer) Strategy(_vaultHealer) {}

    function safeSwap(
        uint256 _amountIn,
        IERC20[] memory path
    ) internal override returns (uint amountOutput) {
        IUniRouter _router = config.router();

        path[0].safeIncreaseAllowance(address(_router), _amountIn);
        
        if (config.feeOnTransfer()) {
            uint balanceBefore = path[path.length - 1].balanceOf(address(this));
            uint amountOutMin = _router.getAmountsOut(_amountIn, path)[path.length - 2] * config.slippageFactor() / 256;

            _router.swapExactTokensForTokensSupportingFeeOnTransferTokens(_amountIn, amountOutMin, path, address(this), block.timestamp);
            amountOutput = path[path.length - 1].balanceOf(address(this)) - balanceBefore;
        } else {
            amountOutput = _router.swapExactTokensForTokens(_amountIn, 0, path, address(this), block.timestamp)[path.length - 2];
        }
    }
}