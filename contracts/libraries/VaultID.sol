// SPDX-License-Identifier: GPLv2
pragma solidity ^0.8.9;

library VaultID {
    using VaultID for Vid;

    type Vid is uint256;

    function isMaximizer(Vid self) internal pure returns (bool) {
        return (Vid.unwrap(self) > 2**16);
    }
    function targetVid(Vid self) internal pure returns (Vid) {
        return Vid.wrap(Vid.unwrap(self) >> 16);
    }

    function next(Vid self) internal pure returns (Vid) {
        uint _vid = Vid.unwrap(self) + 1;
        require(_vid & 0xffff > 0, "Vid: overflow")
        return Vid.wrap(_vid);
    }

}