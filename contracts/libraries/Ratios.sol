// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

library Ratios {

    type Ratio is uint256;

    //uint224: (underlying << 112 / totalshares)
    //uint32: lastUpdateBlock


    function lastUpdateBlock(Ratio self) internal pure returns (uint32) {
        return uint32(Ratio.unwrap(self));
    }

    function underlyingAmount(Ratio self) internal pure returns (uint112) {
        return uint112(Ratio.unwrap(self) >> 144);
    }

    function totalShares(Ratio self) internal pure returns (uint112) {
        return uint112(Ratio.unwrap(self) >> 32);
    }

    function split(Ratio self) internal pure returns (uint112 underlying, uint112 shares, uint32 blockNumber ) {
        return (uint112(Ratio.unwrap(self) >> 144), uint112(Ratio.unwrap(self) >> 32), uint32(Ratio.unwrap(self)));
    }

    function earn(Ratio self, uint112 newUnderlyingAmt) internal view returns (Ratio updated) {
        require((newUnderlyingAmt + 1) << 144 > Ratio.unwrap(self), "Ratio/earn: new underlying must not be smaller");
        return Ratio.wrap((Ratio.unwrap(self) & (type(uint144).max ^ type(uint32).max)) | newUnderlyingAmt << 144 | block.number);
    }
    function deposit(Ratio pool, Ratio account, uint112 depositAmt) internal view returns (Ratio updated) {
        uint pUnderlying = underlyingAmount(pool);
        uint newUnderlying = underlying + depositAmt;
        return Ratio.wrap((newUnderlying << 144) | ((newUnderlying*totalShares(self)/underlying) << 32) | block.number);
    }

    //r = r.withdraw(amt); returns a Ratio with re
    function withdraw(Ratio pool, Ratio account, uint112 withdrawAmt) internal view returns (Ratio updated) {
        uint underlying = underlyingAmount(pool);
        uint newUnderlying = underlying - withdrawAmt;
        return Ratio.wrap((newUnderlying << 144) | ((newUnderlying*totalShares(pool)/underlying) << 32) | block.number);
    }
    

    function harvest(Ratio _pool, Ratio _user) internal view returns (Ratio _pool, Ratio _user) {
        (uint uUnderlying, uint uShares, uint uBlock) = split(_user);
        (uint pUnderlying, uint pShares, uint pBlock) = split(_pool);
        if (pBlock == uBlock) {
            return (_pool, _user);
        }
        



    }



}