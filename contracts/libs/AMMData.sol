/*
Join us at Crystal.Finance!
█▀▀ █▀▀█ █░░█ █▀▀ ▀▀█▀▀ █▀▀█ █░░ 
█░░ █▄▄▀ █▄▄█ ▀▀█ ░░█░░ █▄▄█ █░░ 
▀▀▀ ▀░▀▀ ▄▄▄█ ▀▀▀ ░░▀░░ ▀░░▀ ▀▀▀
*/

pragma solidity ^0.8.4;

/*
This library provides an initial framework for optimized routing and 
functions to manage data specific to UniswapV2-compatible AMMs. The pure
functions inline to constants at compile time, so we can deploy
strategies involving AMMs other than ApeSwap with minimal need to refactor.

Tested with AMMs that implement the standard UniswapV2 swap logic. Not tested with fee on 
transfer tokens. Not likely to work with Firebird, Curve, or DMM without extension.
*/


enum AmmData { PHOTON, CRODEX, CRONA, ELK, NULL }

/*
To retrieve stats, use for example:

    using UniV2AMMData for AmmData; 

    function exampleFunc() internal {
        AmmData _amm = AmmData.PHOTON;
        _amm.factory();
        _amm.pairCodeHash();
        _amm.fee();
    }
*/

library AMMData {
    
    uint constant internal NUM_AMMS = 4;
    
    address constant private PHOTON_FACTORY = 0x462C98Cae5AffEED576c98A55dAA922604e2D875;
    address constant private CRODEX_FACTORY = 0xe9c29cB475C0ADe80bE0319B74AD112F1e80058F;
    address constant private CRONA_FACTORY = 0x73A48f8f521EB31c55c0e1274dB0898dE599Cb11;
    address constant private ELK_FACTORY = 0xEEa0e2830D09D8786Cb9F484cA20898b61819ef1;

    
    //used for internally locating a pair without an external call to the factory
    bytes32 constant private PHOTON_PAIRCODEHASH = hex'01429e880a7972ebfbba904a5bbe32a816e78273e4b38ffa6bdeaebce8adba7c';
    bytes32 constant private CRODEX_PAIRCODEHASH = hex'03f6509a2bb88d26dc77ecc6fc204e95089e30cb99667b85e653280b735767c8';
    bytes32 constant private CRONA_PAIRCODEHASH = hex'c93158cffa5b575e32566e81e847754ce517f8fa988d3e25cf346d916216e06f';
    bytes32 constant private ELK_PAIRCODEHASH = hex'3c1fffa8cacda78be648c67936420eeccee9ff8cd162455b72ddd700b091eaf6';

    
    // Fees are in increments of 1 basis point (0.01%)
    uint constant private PHOTON_FEE = 30; 
    uint constant private CRODEX_FEE = 30;
    uint constant private CRONA_FEE = 25;
    uint constant private ELK_FEE = 30;

    function factoryToAmm(address _factory) internal pure returns(AmmData amm) {
        if (_factory == PHOTON_FACTORY) return AmmData.PHOTON;
        if (_factory == CRODEX_FACTORY) return AmmData.CRODEX;
        if (_factory == CRONA_FACTORY) return AmmData.CRONA;
        if (_factory == ELK_FACTORY) return AmmData.ELK;
        revert("");
    }

    function factory(AmmData _amm) internal pure returns(address) {
        if (_amm == AmmData.PHOTON) return PHOTON_FACTORY;
        if (_amm == AmmData.CRODEX) return CRODEX_FACTORY;
        if (_amm == AmmData.CRONA) return CRONA_FACTORY;   
        if (_amm == AmmData.ELK) return ELK_FACTORY;  
        revert(); //should never happen
    }

    function pairCodeHash(AmmData _amm) internal pure returns(bytes32) {
        if (_amm == AmmData.PHOTON) return PHOTON_PAIRCODEHASH;
        if (_amm == AmmData.CRODEX) return CRODEX_PAIRCODEHASH;
        if (_amm == AmmData.CRONA) return CRONA_PAIRCODEHASH;   
        if (_amm == AmmData.ELK) return ELK_PAIRCODEHASH;  
        revert();
    }
    
    function fee(AmmData _amm) internal pure returns (uint) {
        if (_amm == AmmData.PHOTON) return PHOTON_FEE;
        if (_amm == AmmData.CRODEX) return CRODEX_FEE;
        if (_amm == AmmData.CRONA) return CRONA_FEE;  
        if (_amm == AmmData.ELK) return ELK_FEE;  
        revert();
    }
    
}