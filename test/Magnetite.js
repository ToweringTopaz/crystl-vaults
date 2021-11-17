// import hre from "hardhat";
const { tokens, routers } = require('../configs/addresses.js');
const { WMATIC, CRYSTL, DAI } = tokens.polygon;
const { SUSHISWAP_ROUTER } = routers.polygon;
const { expect } = require('chai');
const { ethers } = require('hardhat');
const { IUniRouter02_abi } = require('./IUniRouter02_abi.js');
const { token_abi } = require('./token_abi.js');
const { IWETH_abi } = require('./IWETH_abi.js');
const { IUniswapV2Pair_abi } = require('./IUniswapV2Pair_abi.js');


describe(`Testing magnetite`, () => {
    before(async () => {
        [user1, user2, user3, _] = await ethers.getSigners();

        Magnetite = await ethers.getContractFactory("Magnetite", {});
        magnetite = await Magnetite.deploy();
        console.log('Magnetite deployed');
        
        routerAddress = SUSHISWAP_ROUTER;
        token1Address = WMATIC;
        token2Address = CRYSTL;

    });

    describe(`Testing magnetite functions`, () => {
        // Create LPs for the vault
        it('findAndSavePath should take a router address and two token addresses and find a path between them', async () => {
            // var routerAddress = SUSHISWAP_ROUTER;
            console.log(routerAddress);
            // var token1Address = WMATIC;
            console.log(token1Address);
            // var token2Address = SUSHI;
            console.log(token2Address);

            var path = await magnetite.findAndSavePath(routerAddress, token1Address, token2Address);
            
            console.log(path[0]);
            console.log(path[1]);
            console.log(path);

            expect(path[0]).to.equal(WMATIC);
        })
    })
})
