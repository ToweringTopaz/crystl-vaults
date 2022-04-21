// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IMasterHealer.sol";

library AmysStakingCo {

    function getMCPoolData(address chef) external view returns (address[] memory lpTokens, uint256[] memory allocPoint) {
        uint len = IMasterHealer(chef).poolLength();

        lpTokens = new address[](len);
        allocPoint = new uint256[](len);

        for (uint i; i < len; i++) {
            (bool success, bytes memory data) = chef.staticcall(abi.encodeWithSignature("poolInfo(uint256)", i));
            if (success) (lpTokens[i], allocPoint[i]) = abi.decode(data,(address, uint256));
        }
    }

}