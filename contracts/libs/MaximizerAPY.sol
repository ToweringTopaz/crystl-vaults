// SPDX-License-Identifier: GPLv2
pragma solidity ^0.8.9;

import "./HardMath.sol";

library MaximizerAPY {

    uint constant PRECISION = 1e18;

    function calculateMaximizerAPY(
        uint pAPR, //annual rate earned on the principal investment, where this value/1e18 is the APR
        uint iAPR, //annual rate earned on the maximizer reinvestment, where this value/1e18 is the APR
        uint n //times compounded per year
    ) external pure returns (uint mAPY) {

        (uint numer, uint denom) = powFraction(PRECISION+iAPR/n, PRECISION, n);

        mAPY = HardMath.mulDiv(HardMath.mulDiv(pAPR,numer,denom) - pAPR, PRECISION, iAPR);
    }

    function calculateAPY(
        uint APR,
        uint n
    ) external pure returns (uint APY) {
    
        (uint numer, uint denom) = powFraction(PRECISION + APR/n, PRECISION, n);
        APY = HardMath.mulDiv(PRECISION,numer,denom) - PRECISION;

    }

    function powFraction(uint _numerator, uint _denominator, uint exp) public pure returns (uint numerator, uint denominator) {
        unchecked {
            require(_denominator > 0, "powFraction div by 0");
            if (exp == 0) {
                require(numerator != 0, "powFraction 0**0");
                return (PRECISION, PRECISION);
            }
            if (_numerator == 0) return (0, PRECISION);
            if (_numerator == _denominator) return (PRECISION,PRECISION);
            
            bool denominatorLarger = _numerator < _denominator;
            if (denominatorLarger) {
                (_numerator, _denominator) = (_denominator, _numerator);
            }
            
            numerator = _numerator;
            denominator = _denominator;
            exp--;

            while(exp > 0) {
                uint c = numerator * _numerator;
                if (c / numerator != _numerator) { //overflow
                    numerator /= _denominator;
                    denominator /= _numerator;
                } else {
                    numerator = c;
                    denominator *= _denominator;
                }
                exp--;
            }
            
            if (denominatorLarger) {
                (numerator, denominator) = (denominator, numerator);
            }
        }
    }
}