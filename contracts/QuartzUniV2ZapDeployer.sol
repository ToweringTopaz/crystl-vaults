// SPDX-License-Identifier: GPLv2

pragma solidity ^0.8.0;

import "./QuartzUniV2Zap.sol";
import "./libs/IVaultHealer.sol";

contract QuartzUniV2ZapDeployer {

    function deployZap() external returns (address quartz) {
        quartz = address(new QuartzUniV2Zap(IVaultHealer(msg.sender)));
    }

}