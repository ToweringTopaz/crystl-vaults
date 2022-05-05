// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MosesFS {

    error AddressCollision();
    error BadRead(uint len, uint size);
    error BadWrite(address deployed, address calculated);
    error CovenantTooLarge();
    error ZeroTablet();

    event TabletCarved(address tablet);

    uint16 constant MAX_DEPLOYED_BYTECODE = 24576;
    bytes32 immutable TABLET_CODE;
    bytes32 constant EMPTY_HASH  = hex'c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470';
    bytes32 constant PILLAR = hex'18beb7d392d5692fcddc3d86a7e1585a3a33802c18b15735d1bd43a26901b05c'; //keccak256("Lot's wife");

    constructor() {
        TABLET_CODE = bytes32(0x383D3D39383Df3fe0000000000000000000000000000000000000000ffff8000 | uint(uint160(address(this)) << 32));
    }

    function find(string memory covenant) external view returns (address tablet, bool carved) {
        return find(bytes(covenant));
    }
    function find(bytes memory covenant) public view returns (address tablet, bool carved) {
        bytes32 hash = hashFor(covenant);
        tablet = computeAddress(hash);
        
        bytes32 mark = tablet.codehash;
        if (mark == hash) carved = true;
        else if (mark != EMPTY_HASH && mark != 0) revert AddressCollision();
    }

    function hashFor(bytes memory covenant) internal view returns (bytes32 hash) {
        bytes32 code = TABLET_CODE;
        assembly ("memory-safe") {
            let len := mload(covenant)
            mstore(covenant, or(len,code)) //temporary write to memory for hashing
            hash := keccak256(covenant, add(len,32))
            mstore(covenant, len) //restore memory to original state
        }
    }

    function computeAddress(bytes32 hash) internal view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), PILLAR, hash)))));
    }

    function write(string memory covenant) external returns (address tablet) {
        return write(bytes(covenant));
    }

    function write(bytes memory covenant) public returns (address tablet) {
        if (covenant.length + 32 > MAX_DEPLOYED_BYTECODE) revert CovenantTooLarge();
        
        bool carved;
        (tablet, carved) = find(covenant);
        if (carved) return tablet;

        address addr;
        bytes32 code = TABLET_CODE;
        assembly ("memory-safe") {
            let len := mload(covenant) //length of bytes in memory
            mstore(covenant, or(len,code)) // overwrite length with tablet initcode/bytecode/first word
            addr := create2(0, covenant, add(len,32), PILLAR) //sending zero value, initcode starts at "covenant", length is that of the data plus one word
            mstore(covenant, len)
        }
        if (addr != tablet) revert BadWrite(addr, tablet);

        emit TabletCarved(tablet);
    }

    function readString(address tablet) external view returns (string memory covenant) {
        return string(read(tablet));
    }

    function read(address tablet) public view returns (bytes memory covenant) {
        
        if (tablet == address(0)) revert ZeroTablet();

        uint size;
        bytes32 code = TABLET_CODE;
        assembly ("memory-safe") {
            covenant := mload(0x40)
            size := extcodesize(tablet)
            mstore(0x40, add(covenant, size))
            
            extcodecopy(tablet, covenant, 0, size)
            let len := xor(code, mload(covenant))
            mstore(covenant, len)
        }
        unchecked {
            if (covenant.length + 32 != size) revert BadRead(covenant.length, size);
        }
    
    }

}