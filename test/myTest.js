// import hre from "hardhat";

const { accounts, tokens, masterChefs, lps, routers } = require('../configs/addresses.js');
const { QUICK, WMATIC, CRYSTL, KOM, DAI } = tokens.polygon;
const { quickVaults } = require('../configs/quickVaults');
const { expect } = require('chai');
const { ethers } = require('hardhat');
// const { IUniRouter02_abi } = require('./IUniRouter02_abi.js');
const { IUniRouter02_abi } = require('./IUniRouter02_abi.js');
const { token_abi } = require('./token_abi.js');


describe('Token contract', () => {
    let StrategyMasterHealerForQuick, strategyMasterHealerForQuick, owner, addr1, addr2;

    beforeEach(async () => {
        StrategyMasterHealerForQuick = await ethers.getContractFactory('StrategyMasterHealerForQuick');
        strategyMasterHealerForQuick = await StrategyMasterHealerForQuick.deploy(quickVaults[0].addresses, ...quickVaults[0].strategyConfig);
        [owner, addr1, addr2, _] = await ethers.getSigners();

        VaultHealer = await ethers.getContractFactory('VaultHealer');
        testVaultHealer = await VaultHealer.deploy();

        testVaultHealer.addPool(strategyMasterHealerForQuick.address);

        uniswapRouter = await ethers.getContractAt(IUniRouter02_abi, routers.polygon.QUICKSWAP_ROUTER);
        console.log(owner.address);

        await network.provider.send("hardhat_setBalance", [
            owner.address,
            "0x3635c9adc5dea00000",
        ]);

        console.log(await owner.getBalance());

        await owner.sendTransaction({
            to: addr1.address,
            value: ethers.utils.parseEther("100")
        });

        await uniswapRouter.swapExactETHForTokens(0, [WMATIC, QUICK], owner.address, Date.now() + 900, { value: ethers.utils.parseEther("100") })
        await uniswapRouter.swapExactETHForTokens(0, [WMATIC, KOM], owner.address, Date.now() + 900, { value: ethers.utils.parseEther("100") })

        quick = await ethers.getContractAt(token_abi, QUICK);
        var quickBalance = await quick.balanceOf(owner.address);
        console.log(quickBalance)
        await quick.approve(uniswapRouter.address, quickBalance)

        kom = await ethers.getContractAt(token_abi, KOM);
        var komBalance = await kom.balanceOf(owner.address)
        console.log(komBalance);
        await kom.approve(uniswapRouter.address, komBalance)

        await uniswapRouter.addLiquidity(QUICK, KOM, quickBalance, komBalance, 0, 0, owner.address, Date.now() + 900)
        //TODO - change min amounts out from zero?

        // await hre.network.provider.request({
        //     method: "hardhat_impersonateAccount",
        //     params: [WHALE],
        //   });
    });

    describe('Deployment', () => {
        it('Should set the right Masterchef address', async () => {
            expect(await strategyMasterHealerForQuick.masterchefAddress()).to.equal(masterChefs.polygon.QUICK_MASTERCHEF);
        })


        // it('should assign the total supply of tokens to the owner', async () => {
        //     const ownerBalance = await token.balanceOf(owner.address);
        //     expect(await token.totalSupply()).to.equal(ownerBalance);
        // })
    })

    describe('Transactions', () => {
        it('Should deposit whole balance of LP tokens into farm', async () => {
            LPtoken = await ethers.getContractAt(token_abi, lps.polygon.QUICK_KOM_QUICK_LP);
            var LPtokenBalance = await LPtoken.balanceOf(owner.address);
            console.log(LPtokenBalance);
            await LPtoken.approve(uniswapRouter.address, LPtokenBalance);
            await testVaultHealer.deposit(0, LPtokenBalance); //owner (default signer) deposits 100 of LP tokens into pid 0 of vaulthealer
            
            LPtokenBalanceAfter = await LPtoken.balanceOf(owner.address);
            expect(LPtokenBalanceAfter).to.equal(0);

            // await token.connect(addr1).transfer(addr2.address, 50);
            // const adddr2Balance = await token.balanceOf(addr2.address);

        })
    })
})