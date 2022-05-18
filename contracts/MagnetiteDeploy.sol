// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "./Magnetite.sol";
contract MagnetiteDeploy {

    event ProxyBeacon(address beacon, address proxy);

        Magnetite public immutable implementation;
        UpgradeableBeacon public immutable beacon;
        BeaconProxy public immutable proxy;


    constructor(address vhAuth) {
        implementation = new Magnetite(vhAuth);
        beacon = new UpgradeableBeacon(address(implementation));
        beacon.transferOwnership(msg.sender);
        proxy = new BeaconProxy(address(beacon), "");

        Magnetite(address(proxy))._init(vhAuth);

    }


}