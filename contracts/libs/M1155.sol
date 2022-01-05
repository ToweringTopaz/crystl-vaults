// SPDX-License-Identifier: GPLv3

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

//For Maximizer1155 related functions and structures

library M1155 {
    using EnumerableSet for EnumerableSet.UintSet;
    type UserAmounts is uint256; //112 balance, 112 rewardDebt, 32 refs
    type TokenSupply is uint256; //112 totalSupply, 112 virtualSupply
    type EarnRatio is uint256;

    uint24 constant MAX_VID = 0xeeeeed;
    uint240 constant MAX_MAXIMIZER_TOKENID = type(uint240).max;

    struct AccountInfo {
        UserAmounts amounts; //balance, rewardDebt (virtualBalance for maximizer accounts), lastUpdateBlock
        EnumerableSet.UintSet maximizersIn; //all maximizer tokens directed here, of which the user has shares

    }
    struct TokenInfo {
        bool enabled; //are deposits to this allowed?
        uint112 totalSupply; //total supply for this token

        mapping(address => AccountInfo) user; //user's account for this token (balance, rewardDebt, lastUpdateBlock)
        mapping(uint256 => AccountInfo) maximizer; //maximizer's account for this token
    }

/*  
 *  For encoding/decoding UserAmounts
 */
    function getBalance(UserAmounts user) internal pure returns (uint256) {
        return UserAmounts.unwrap(user) >> 144;
    }
    function getRewardDebt(UserAmounts user) internal pure returns (uint256) {
        return (UserAmounts.unwrap(user) >> 32) & type(uint112).max;
    }
    function getLastUpdateBlock(UserAmounts user) internal pure returns (uint256) {
        return UserAmounts.unwrap(user) & type(uint32).max;
    }
    function decode(UserAmounts user) internal pure returns (uint256 _balance, uint256 _rewardDebt, uint256 _lastUpdateBlock) {
        return decode112x112x32(UserAmounts.unwrap(user));
    }
    function encodeUserAmounts(uint256 balance, uint256 rewardDebt) internal view returns (UserAmounts) {
        return UserAmounts.wrap(encode112x112x32(balance, rewardDebt, block.number));
    }
    function encode112x112x32(uint256 a, uint256 b, uint256 c) private pure returns (uint256 value) {
        require(a < 2**112 && b < 2**112 && c < 2**32, "M1155: 112x112x32 overflow");
        value = (a << 144) | (b << 32) | c;
    }
    function decode112x112x32(uint256 value) private pure returns (uint a, uint b, uint c) {
        a = value >> 144;
        b = value >> 32 & type(uint112).max;
        c = value & type(uint32).max;
    }

/*
 *  TokenID and VaultID numeric functons
 */

    function isAutocompounder(uint _id) internal pure returns (bool) {
        return _id == (_id & 0xffffff) && _id > 0;
    }
    function isMaximizer(uint _id) internal pure returns (bool) {
        return (_id & 0xffffff) > 0 && (_id >> 224) == 0;
    }
    function isVaultToken(uint _id) internal pure returns (bool) {
        return (_id > 0 && _id < type(uint232).max);
    }
    function targetOf(uint _id) internal pure returns (uint targetID) {
        targetID = _id >> 24;
        assert(targetID != _id);
    }
    function vaultOf(uint24 _tid) internal pure returns (uint24 vid) {
        return _tid & type(uint24).max;
    }
/*
 *  EarnRatio functions
 */

    function toRatio(uint newAmount, uint oldAmount) internal view returns (EarnRatio) {
        require(newAmount >= oldAmount, "M1155: Bad ratio"); //tx would reduce earnings total
        if (oldAmount == 0) return EarnRatio.wrap(encode112x112x32(1, 1, block.number));
        return EarnRatio.wrap(encode112x112x32(1, 1, block.number));
    }
    function decode(EarnRatio ratio) internal pure returns (uint numerator, uint denominator, uint updateBlock) {
        (numerator, denominator, updateBlock) = decode112x112x32(EarnRatio.unwrap(ratio));
        assert(denominator > 0);

    }
    function mul(uint amount, EarnRatio ratio) internal pure returns (uint amountAfter) {
        (uint numerator, uint denominator,) = decode(ratio);
        assert(denominator > 0);
        amountAfter = amount * numerator / denominator;
        require(amountAfter < 2**112, "M1155: mul112 overflow");
    }
    function div(uint amount, EarnRatio ratio) internal pure returns (uint amountAfter) {
        (uint numerator, uint denominator,) = decode(ratio);
        assert(numerator > 0);
        amountAfter = amount * denominator / numerator;
        require(amountAfter < 2**112, "M1155: div112 overflow");
    }

}