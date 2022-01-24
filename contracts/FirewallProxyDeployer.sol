// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./libs/FirewallProxies.sol";
import "./FirewallProxyImplementation.sol";

//Contracts which deploy FirewallProxy should inherit this
abstract contract FirewallProxyDeployer {

    address tempImplementation;
    bytes tempData;

    //used by the proxy constructor to generate the final bytecode
    function getProxyData() external returns (address implementation, bytes memory data) {
        implementation = tempImplementation;
        data = tempData;
        delete tempImplementation;
        delete tempData;
    }

    //creates a new firewallproxy. Address wil be purely determined by salt and deployer address
    //implementation must implement FirewallProxyImplementation and itself not be a proxy
    function deployProxy(address implementation, bytes32 salt, bytes calldata data) internal returns (address proxyAddress) {
        try FirewallProxyImplementation(implementation).isFirewallProxyBareImplementation() returns (bool isBareImpl) {
            require(isBareImpl, "target must be impl. not proxy");
        } catch {
            revert("bad impl target");
        }
        tempImplementation = implementation;
        tempData = data;
        proxyAddress = FirewallProxies.deploy(salt);
    }

}