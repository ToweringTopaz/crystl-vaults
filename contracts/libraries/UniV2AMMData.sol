// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

/*
This library provides an initial framework for optimized routing and 
functions to manage data specific to UniswapV2-compatible AMMs. The pure
functions inline to constants at compile time, so we can deploy
strategies involving AMMs other than ApeSwap with minimal need to refactor.

Tested with AMMs that implement the standard UniswapV2 swap logic. Not tested with fee on 
transfer tokens. Not likely to work with Firebird, Curve, or DMM without extension.
*/


enum AmmData { APE, QUICK, SUSHI, DFYN }


/*
To retrieve stats, use for example:

    using UniV2AMMData for AmmData; 

    function exampleFunc() internal {
        AmmData _amm = AmmData.APE;
        _amm.factory();
        _amm.pairCodeHash();
        _amm.fee();
    }
*/

library UniV2AMMData {
    
    address constant private APE_FACTORY = 0xCf083Be4164828f00cAE704EC15a36D711491284;
    address constant private QUICK_FACTORY = 0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32;
    address constant private SUSHI_FACTORY = 0xc35DADB65012eC5796536bD9864eD8773aBc74C4;
    address constant private DFYN_FACTORY = 0xE7Fb3e833eFE5F9c441105EB65Ef8b261266423B;
    
    //used for internally locating a pair without an external call to the factory
    bytes32 constant private APE_PAIRCODEHASH = hex'511f0f358fe530cda0859ec20becf391718fdf5a329be02f4c95361f3d6a42d8';
    bytes32 constant private QUICK_PAIRCODEHASH = hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f';
    bytes32 constant private SUSHI_PAIRCODEHASH = hex'e18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303';
    bytes32 constant private DFYN_PAIRCODEHASH = hex'f187ed688403aa4f7acfada758d8d53698753b998a3071b06f1b777f4330eaf3';

    // Fees are in increments of 10 basis points (0.10%)
    uint constant private APE_FEE = 2; 
    uint constant private QUICK_FEE = 3;
    uint constant private SUSHI_FEE = 3;
    uint constant private DFYN_FEE = 3;

    function factory(AmmData _amm) internal pure returns(address) {
        if (_amm == AmmData.APE) return APE_FACTORY;
        if (_amm == AmmData.QUICK) return QUICK_FACTORY;
        if (_amm == AmmData.SUSHI) return SUSHI_FACTORY;
        if (_amm == AmmData.DFYN) return DFYN_FACTORY;
        revert(); //should never happen
    }

    function pairCodeHash(AmmData _amm) internal pure returns(bytes32) {
        if (_amm == AmmData.APE) return APE_PAIRCODEHASH;
        if (_amm == AmmData.QUICK) return QUICK_PAIRCODEHASH;
        if (_amm == AmmData.SUSHI) return SUSHI_PAIRCODEHASH;
        if (_amm == AmmData.DFYN) return DFYN_PAIRCODEHASH;
        revert();
    }
    
    function fee(AmmData _amm) internal pure returns (uint) {
        if (_amm == AmmData.APE) return APE_FEE;
        if (_amm == AmmData.QUICK) return QUICK_FEE;
        if (_amm == AmmData.SUSHI) return SUSHI_FEE;
        if (_amm == AmmData.DFYN) return DFYN_FEE;
        revert();
    }
    
}