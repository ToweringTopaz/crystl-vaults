// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import "./Magnetite.sol";

//Automatically generates and stores paths
contract MagnetiteCronos is Magnetite {

    function commonTokens(IUniRouter router) internal pure override returns (IERC20[] memory tokens) {
        tokens = new IERC20[](6);
        tokens[0] = router.WETH();
        tokens[1] = IERC20(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d); //usdc
        tokens[2] = IERC20(0x2170Ed0880ac9A755fd29B2688956BD959F933F8); //weth
        tokens[3] = IERC20(0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c); //wbtc: actually btcb on BNB Chain
        tokens[4] = IERC20(0x55d398326f99059fF775485246999027B3197955); //usdt
        tokens[5] = IERC20(0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3); //dai
    }

    function _init() internal view override {
        require(block.chainid == 56, "not bnb chain");
    }

}