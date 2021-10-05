// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

type bool256 is uint256;

//A value type which holds up to 256 boolean values in the form of a uint
library Boolean256 {

    //retrieves a single bool from the bool256
    function get(bool256 b, uint i) internal pure returns (bool) {
        uint _b = bool256.unwrap(b);
        return (_b >> i) % 2 != 0;
    }
    
    //sets a single bool value in the bool256
    function set(bool256 b, uint i, bool value) internal pure returns (bool256) {
        require(i < 256, "bool256: out of bounds");
        uint _b = bool256.unwrap(b);
        return value ? bool256.wrap(_b | (1 << i)) : bool256.wrap(_b ^ (1 << i));
    }
    
    //sets all 256 variables to true or false
    function setAll(bool256, bool value) internal pure returns (bool256) {
        return value ? bool256.wrap(type(uint).max) : bool256.wrap(0);
    }
    
    //returns the first true index starting at 'from'. A return value of 256 means none found.
    //255 is the default ending "to" value if not specified
    function next(bool256 b, uint from) public pure returns (uint n) {
        return next(b,from,255);
    }
    function next(bool256 b, uint from, uint to) public pure returns (uint n) {
        require(to < 257, "bool256: invalid to index");
        uint _b = bool256.unwrap(b);
        if (from > to || from >= _b) return 256;

        _b >>= from;
        for (n = from; n < to; n++) { //TODO: should be optimized
            if (_b % 2 == 1) return n;
        }
        return n;
    }
        
}
    