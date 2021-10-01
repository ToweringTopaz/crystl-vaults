// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BaseStrategyIndependent.sol";

abstract contract BaseStrategyMaxiCore is BaseStrategyIndependent {
    
    //Maximizer-incapable strategies throw
    //Maximizer suppliers return address(0)
    //Maximizer cores return their want address
    function maximizerInfo() external view override returns (address maxiToken) {
        return addresses.want;
    }

    mapping (address => address) public maxiImports; //supplier => import tokens
    
    function _transferShares(address _from, address _to, uint _amount) {
           
    }

}