// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import "./Magnetite.sol";

//Automatically generates and stores paths
contract MagnetiteCronos is Magnetite {

    function commonTokens(IUniRouter router) internal pure override returns (IERC20[] memory tokens) {
        tokens = new IERC20[](6);
        tokens[0] = router.WETH();
        tokens[1] = IERC20(0xc21223249CA28397B4B6541dfFaEcC539BfF0c59); //usdc
        tokens[2] = IERC20(0xe44Fd7fCb2b1581822D0c862B68222998a0c299a); //weth
        tokens[3] = IERC20(0x062E66477Faf219F25D27dCED647BF57C3107d52); //wbtc
        tokens[4] = IERC20(0x66e428c3f67a68878562e79A0234c1F83c208770); //usdt
        tokens[5] = IERC20(0xF2001B145b43032AAF5Ee2884e456CCd805F677D); //dai
    }

    function _init() internal view override {
        require(block.chainid == 25, "not cronos chain");
    }

}