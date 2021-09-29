// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BaseStrategyIndependent.sol";

abstract contract BaseStrategyMaxiCore is BaseStrategyIndependent {
    
    struct UserInfo {
        uint256 shares; // How many LP tokens the user has provided.
        uint256[] mShares;
    }
    
    //Maximizer-incapable strategies throw
    //Maximizer suppliers return address(0)
    //Maximizer cores return their want address
    function maximizerInfo() external view returns (address maxiToken) {
        return addresses.want;
    }

}