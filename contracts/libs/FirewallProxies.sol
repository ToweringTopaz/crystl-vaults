// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Create2Upgradeable as Create2} from "@openzeppelin/contracts-upgradeable/utils/Create2Upgradeable.sol";

import "./IFirewallProxy.sol";
import "../FirewallProxy.sol";

library FirewallProxies {

    bytes constant public CODE = type(FirewallProxy).creationCode;
    bytes32 constant public CODE_HASH = keccak256(CODE);

    function codeLength() external pure returns (uint) {
        return CODE.length;
    }

    function sizeOf(address a) public view returns (uint size) {
        assembly {
            size := extcodesize(a)
        }
    }

    function deploy(bytes32 salt) external returns (address) {
        return Create2.deploy(0, salt, CODE);
    }

    //Returns metadata stored in a proxy contract after the executable proxy code
    function dataOf(address proxy) public view returns (bytes memory data) { //todo: analyze gas and codesize effects: if internal, does the whole code get copied or just its length?
        uint codelen = CODE.length;
        uint proxysize = sizeOf(proxy);
        require(proxysize >= codelen, "dataOf bad firewall proxy");
        uint metadatasize = proxysize - codelen; //size of data after executable
        data = new bytes(metadatasize); //allocate return variable's memory and set length
        assembly {
            extcodecopy(proxy, add(data,0x20), codelen, metadatasize) //copy the data from proxy's code to memory
        }
    }

    function dataOf(address proxy, uint offset, uint len) public view returns (bytes memory data) {
        uint codelen = CODE.length;
        uint proxysize = sizeOf(proxy);
        data = new bytes(len); //allocate return variable's memory and set length
        assembly {
            extcodecopy(proxy, add(data,0x20), add(offset,codelen), len) //copy the data from proxy's code to memory
        }        
    }

    //recomputes a proxy's address; cheaper than using storage
    function computeAddress(bytes32 salt) internal view returns (address) {
        return Create2.computeAddress(salt, CODE_HASH, address(this));
    }
    function computeAddress(bytes32 salt, address deployer) internal pure returns (address) {
        return Create2.computeAddress(salt, CODE_HASH, deployer);
    }

    //selfdestructs a proxy contract (must be called as deployer); returns the contract's data store
    function destroyProxy(address proxy) external returns (bytes memory data) {
        data = dataOf(proxy);
        IFirewallProxy(proxy)._destroy_();
    }
}
contract Test {

    function cl() external view returns (uint)
    
}