// SPDX-License-Identifier: MIT
pragma solidity >=0.4.0;

import "./FullMath.sol";
//Just some helpful math functions


library MoreMath {
    
    
    function mulDiv(
        uint256 a,
        uint256 b,
        uint256 denominator,
        bool negative
    ) internal pure returns (int256 result) {
        result = negative ? -int(FullMath.mulDiv(a, b, denominator)) : int(FullMath.mulDiv(a, b, denominator));
    }
    
    //muldiv starting with signed ints
    function mulDiv(
        int256 a,
        int256 b,
        int256 denominator
    ) internal pure returns (int256 result) {
        bool neg = (a < 0) != (b < 0) != (denominator < 0);
        
        return mulDiv(abs(a), abs(b), abs(denominator), neg);
    }
    function mulDiv(
        int256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (int256 result) {
        bool neg = (a < 0);
        
        return mulDiv(abs(a), b, denominator, neg);
    }
    function mulDiv(
        uint256 a,
        int256 b,
        uint256 denominator
    ) internal pure returns (int256 result) {
        bool neg = (b < 0);
        
        return mulDiv(a, abs(b), denominator, neg);
    }
    
    function abs(int256 a) internal pure returns (uint256 result) {
        return a > 0 ? uint256(a) : uint256(-a);
    }
    
}