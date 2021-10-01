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
    
    mapping (address => bool) public isSupplier;
    mapping (address => address[]) public userSuppliers; //all suppliers where a user has shares
    
    modifier onlySupplier() {
        require(isSupplier[msg.sender], "caller must be a supplier contract");
        _;
    }
    
    function transferShares(address _to, uint _amount) external nonReentrant onlySupplier {
        userInfo[msg.sender].shares -= _amount;
        userInfo[_to].shares += _amount;
    }
    
    function addUserSupplier(address _user) external onlySupplier {
        address[] storage uS = userSuppliers[_user];
        for (uint i; i < uS.length; i++) {
            if (uS[i] == msg.sender) return;
        }
        uS.push() = msg.sender;
    }
    function removeUserSupplier(address _user) external onlySupplier {
        address[] storage uS = userSuppliers[_user];
        for (uint i; i < uS.length; i++) {
            if (uS[i] == msg.sender) {
                uS[i] = uS[uS.length - 1];
                uS.pop();
            }
        }
    }
}