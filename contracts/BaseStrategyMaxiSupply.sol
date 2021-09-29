// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BaseStrategyIndependent.sol";

abstract contract BaseStrategyMaxiSupply is BaseStrategyIndependent {
    
    //Maximizer-incapable strategies throw
    //Maximizer suppliers return address(0)
    //Maximizer cores return their want address
    function maximizerInfo() external pure returns (address maxiToken) {
        return address(0);
    }
}