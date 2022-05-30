// SPDX-License-Identifier: MIT
///@author ToweringTopaz

pragma solidity ^0.8.14;

library Moses {

    error AddressCollision();
    error BadRead();
    error BadWrite(address deployed, address calculated);
    error CovenantTooLarge();
    error ZeroTablet();

    bytes32 constant EMPTY_HASH  = hex'c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470';
    bytes32 constant PILLAR = hex'18beb7d392d5692fcddc3d86a7e1585a3a33802c18b15735d1bd43a26901b05c'; //keccak256("Lot's wife");

    MosesFS constant MOSES_FS = MosesFS(0x7C7C7c7c7C7C7c7C7c7c7C7C7c7c7C7C7c7c7c7C);
    bytes32 constant TABLET_CODE = hex'383D3D39383Df3fe7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7cffff8000';

    function find(bytes memory covenant) internal view returns (address tablet, bool carved) {

        bytes32 hash = hashFor(covenant);
        tablet = computeAddress(hash);
        
        bytes32 mark = tablet.codehash;
        if (mark == hash) carved = true;
        else if (mark != EMPTY_HASH && mark != 0) revert AddressCollision();
    }

    function find(string memory covenant) internal view returns (address tablet, bool carved) {
        return find(bytes(covenant));
    }
    
    function hashFor(bytes memory covenant) private pure returns (bytes32 hash) {
        assembly ("memory-safe") {
            let len := mload(covenant)
            mstore(covenant, or(len,TABLET_CODE)) //temporary write to memory for hashing
            hash := keccak256(covenant, add(len,32))
            mstore(covenant, len) //restore memory to original state
        }
    }

    function computeAddress(bytes32 hash) public pure returns (address addr) {
        assembly {
            let ptr := mload(0x40) //free memory pointer, which is temporarily overwritten
            mstore(0x40, hash) 
            mstore(0x20, PILLAR) //solidity scratch space
            mstore(0x00, 0xff7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c)
            addr := keccak256(11,85)
            mstore(0x40, ptr)
        }
    }

    function write(string memory covenant) internal returns (address tablet) {
        return MOSES_FS.write(covenant);
    }

    function write(bytes memory covenant) internal returns (address tablet) {
        return MOSES_FS.write(covenant);
    }

    function readString(address tablet) internal view returns (string memory covenant) {
        return string(read(tablet));
    }

    function read(address tablet) internal view returns (bytes memory covenant) {
        
        if (tablet == address(0)) revert ZeroTablet();

        uint size = tablet.code.length;

        assembly ("memory-safe") {
            covenant := mload(0x40)
            mstore(0x40, add(covenant, size))
            
            extcodecopy(tablet, covenant, 0, size)
            size := sub(size, 32)
            let len := xor(TABLET_CODE, mload(covenant))
            mstore(covenant, len)
        }
        
        if (covenant.length != size) revert BadRead();
    }

}

contract MosesFS {

    uint16 constant MAX_DEPLOYED_BYTECODE = 24576;
    uint16 constant MAX_LENGTH = MAX_DEPLOYED_BYTECODE - 32;
    bytes32 constant PILLAR = hex'18beb7d392d5692fcddc3d86a7e1585a3a33802c18b15735d1bd43a26901b05c'; //keccak256("Lot's wife");
    bytes32 constant TABLET_CODE = hex'383D3D39383Df3fe7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7cffff8000';

    function find(string memory covenant) external view returns (address tablet, bool carved) {
        return Moses.find(covenant);
    }
    function find(bytes memory covenant) external view returns (address tablet, bool carved) {
        return Moses.find(covenant);
    }

    function computeAddress(bytes32 hash) external pure returns (address) {
        return Moses.computeAddress(hash);
    }

    function write(string memory covenant) external returns (address tablet) {
        return write(bytes(covenant));
    }
    
    function write(bytes memory covenant) public returns (address tablet) {
        if (covenant.length > MAX_LENGTH) revert Moses.CovenantTooLarge();
        
        bool carved;
        (tablet, carved) = Moses.find(covenant);
        if (!carved) {
            address addr = _write(covenant);
            if (addr != tablet) revert Moses.BadWrite(addr, tablet);
        }
    }

    function _write(bytes memory covenant) public returns (address tablet) {
        assembly ("memory-safe") {
            let len := mload(covenant) //length of bytes in memory
            mstore(covenant, or(len,TABLET_CODE)) // overwrite length with tablet initcode/bytecode/first word
            tablet := create2(0, covenant, add(len,32), PILLAR) //sending zero value, initcode starts at "covenant", length is that of the data plus one word
            mstore(covenant, len)
        }
        emit Moses.TabletCarved(tablet);
    }

    function readString(address tablet) external view returns (string memory covenant) {
        return string(Moses.read(tablet));
    }

    function read(address tablet) external view returns (bytes memory covenant) {
        return Moses.read(tablet);
    }

}