// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./libs/FirewallProxies.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

//Contracts which are designed for FirewallProxy should inherit this
abstract contract FirewallProxyImplementation is Initializable {

    address immutable public IMPLEMENTATION_ADDRESS = address(this); //to access even if delegated

    //returns true if bare impl, false if behind proxy, generally expected to revert if not a FirewallProxyImplementation at all
    function isFirewallProxyBareImplementation() public view returns (bool) {
        return IMPLEMENTATION_ADDRESS == address(this);
    }

    function getProxyData() internal view returns (bytes memory data) {
        require (!isFirewallProxyBareImplementation(), "must be used with a proxy");
        return FirewallProxies.dataOf(address(this));
    }
    function _destroy_() external pure {
        revert("Cannot destroy implementation contract");
    }
    function beforeProxyDestruction() external virtual {
        
    }

}
