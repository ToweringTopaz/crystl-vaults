
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;


library Cavendish {

    bytes12 constant PROXY_INIT_CODE = hex'602d3481343434335afa50f3';
    bytes32 constant PROXY_INIT_HASH = keccak256(abi.encodePacked(PROXY_INIT_CODE));

    function computeAddress(bytes32 salt) internal view returns (address) {
        return computeAddress(salt, address(this));
    }

    function computeAddress(
        bytes32 salt,
        address deployer
    ) internal pure returns (address) {
        bytes32 _data = keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, PROXY_INIT_HASH));
        return address(uint160(uint256(_data)));
    }

}