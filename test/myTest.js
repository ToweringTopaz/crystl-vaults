// import hre from "hardhat";

const { accounts, tokens, masterChefs, lps, routers } = require('../configs/addresses.js');
const { QUICK, WMATIC, CRYSTL, KOM, DAI } = tokens.polygon;
const { quickVaults } = require('../configs/quickVaults');
const { expect, assert } = require('chai');
const { ethers } = require('hardhat');
// const { IUniRouter02_abi } = require('./IUniRouter02_abi.js');
const { IUniRouter02_abi } = require('./IUniRouter02_abi.js');
const { token_abi } = require('./token_abi.js');
const { vaultHealer_abi } = require('./vaultHealer_abi.js');


describe('StrategyMasterHealer contract', () => {
    let StrategyMasterHealerForQuick, strategyMasterHealerForQuick, owner, addr1, addr2;

    before(async () => {
        [owner, addr1, addr2, _] = await ethers.getSigners();
        StrategyMasterHealerForQuick = await ethers.getContractFactory('StrategyMasterHealerForQuick');
        strategyMasterHealerForQuick = await StrategyMasterHealerForQuick.deploy(quickVaults[0].addresses, ...quickVaults[0].strategyConfig);
        
        vaultHealer = await ethers.getContractAt(vaultHealer_abi, accounts.polygon.NEW_TEST_VAULT_HEALER);

        TEST_VAULTHEALER_OWNER = "0x6c4242cbE5b658DA0a9440F90bB3AFD31975418D";
        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [TEST_VAULTHEALER_OWNER],
          });
        TEST_VAULTHEALER_OWNER_SIGNER = await ethers.getSigner(TEST_VAULTHEALER_OWNER)

        await vaultHealer.connect(TEST_VAULTHEALER_OWNER_SIGNER).addPool(strategyMasterHealerForQuick.address);
        // console.log(await vaultHealer.poolLength());

        uniswapRouter = await ethers.getContractAt(IUniRouter02_abi, routers.polygon.QUICKSWAP_ROUTER);
        // console.log(owner.address);
        
        await network.provider.send("hardhat_setBalance", [
            owner.address,
            "0x3635c9adc5dea00000",
        ]);

        // console.log(await owner.getBalance());

        // await owner.sendTransaction({
        //     to: addr1.address,
        //     value: ethers.utils.parseEther("100")
        // });

        await uniswapRouter.swapExactETHForTokens(0, [WMATIC, QUICK], owner.address, Date.now() + 900, { value: ethers.utils.parseEther("100") })
        await uniswapRouter.swapExactETHForTokens(0, [WMATIC, KOM], owner.address, Date.now() + 900, { value: ethers.utils.parseEther("100") })

        //TODO - change min amounts out from zero?
        
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
        // Create LPs for the vault
        it('Should create the right LP tokens for owner to stake in the vault', async () => {
            quick = await ethers.getContractAt(token_abi, QUICK);
            var quickBalance = await quick.balanceOf(owner.address);
            await quick.approve(uniswapRouter.address, quickBalance);
    
            kom = await ethers.getContractAt(token_abi, KOM);
            var komBalance = await kom.balanceOf(owner.address);
            await kom.approve(uniswapRouter.address, komBalance);

            await uniswapRouter.addLiquidity(QUICK, KOM, quickBalance, komBalance, 0, 0, owner.address, Date.now() + 900)
            LPtoken = await ethers.getContractAt(token_abi, lps.polygon.QUICK_KOM_QUICK_LP);
            LPtokenBalance = await LPtoken.balanceOf(owner.address);
            // console.log(LPtokenBalance);
            expect(LPtokenBalance).to.not.equal(0);
        })
        // Stake a round number of LPs (e.g., 1 or 0.0001)
        it('Should deposit whole balance of LP tokens into farm', async () => {
            await LPtoken.approve(vaultHealer.address, LPtokenBalance); //no, I have to approve the vaulthealer surely?
            // console.log(await vaultHealer.owner());
            // console.log(vaultHealer.address)
            poolLength = await vaultHealer.poolLength()
            LPtokenBalanceBefore = await LPtoken.balanceOf(owner.address);
            // console.log(LPtokenBalanceBefore);
            await vaultHealer["deposit(uint256,uint256)"](poolLength-1,LPtokenBalance); //owner (default signer) deposits 1 of LP tokens into pid 0 of vaulthealer
            LPtokenBalanceAfter = await LPtoken.balanceOf(owner.address);

            // console.log(LPtokenBalanceAfter);

            LPtokenBalanceAfter = await LPtoken.balanceOf(owner.address);
            vaultSharesTotalAfter = await strategyMasterHealerForQuick.connect(TEST_VAULTHEALER_OWNER_SIGNER).vaultSharesTotal() //=0
            // console.log(vaultSharesTotalAfter
            expect(LPtokenBalanceBefore).to.equal(vaultSharesTotalAfter);
           

            // await token.connect(addr1).transfer(addr2.address, 50);
            // const adddr2Balance = await token.balanceOf(addr2.address);

        })
        // Compound LPs (Call the earnSome function with this specific farm’s pid).
        // Check balance to ensure it increased as expected
        it('Should compound the LPs', async () => {
            //poolLength = await vaultHealer.poolLength()
            vaultSharesTotalBefore = await strategyMasterHealerForQuick.connect(TEST_VAULTHEALER_OWNER_SIGNER).vaultSharesTotal()
            await vaultHealer.earnSome([poolLength-1]);
            vaultSharesTotalAfter = await strategyMasterHealerForQuick.connect(TEST_VAULTHEALER_OWNER_SIGNER).vaultSharesTotal()
            // console.log(vaultSharesTotalAfter)
            // console.log(vaultSharesTotalBefore)
            assert.isAbove(vaultSharesTotalAfter.toNumber(), vaultSharesTotalBefore.toNumber(), "Vault Shares go up after compounding");
        })
        // follow the flow of funds in the transaction to ensure burn, compound fee, and LP creation are all accurate.
        it('Should burn x amount of crystal with each earn, pay y fee to compound, and create z LPs when it compounds', async () => {
            // //poolLength = await vaultHealer.poolLength()
            // vaultSharesTotalBefore = await strategyMasterHealerForQuick.vaultSharesTotal()
            // await vaultHealer.earnSome([poolLength-1]);
            // vaultSharesTotalAfter = await strategyMasterHealerForQuick.vaultSharesTotal()
            // expect(vaultSharesTotalAfter).greaterThan(vaultSharesTotalBefore);
        })
        // Unstake 50% of LPs. 
        // Check transaction to ensure withdraw fee amount is as expected and amount withdrawn in as expected
        it('Should unstake 50% of LPs with correct withdraw fee amount and balance changes', async () => {
            // //poolLength = await vaultHealer.poolLength()
            // vaultSharesTotalBefore = await strategyMasterHealerForQuick.vaultSharesTotal()
            // await vaultHealer.earnSome([poolLength-1]);
            // vaultSharesTotalAfter = await strategyMasterHealerForQuick.vaultSharesTotal()
            // expect(vaultSharesTotalAfter).greaterThan(vaultSharesTotalBefore);
        })
        // Deposit 100%, ensure balance increases as expected.
        it('Should accurately increase balance at second deposit', async () => {
            // //poolLength = await vaultHealer.poolLength()
            // vaultSharesTotalBefore = await strategyMasterHealerForQuick.vaultSharesTotal()
            // await vaultHealer.earnSome([poolLength-1]);
            // vaultSharesTotalAfter = await strategyMasterHealerForQuick.vaultSharesTotal()
            // expect(vaultSharesTotalAfter).greaterThan(vaultSharesTotalBefore);
        })
        // Withdraw 100%, ensure no funds left in the vault.
        it('Should leave zero funds in vault upon 100% withdrawal', async () => {
            // //poolLength = await vaultHealer.poolLength()
            // vaultSharesTotalBefore = await strategyMasterHealerForQuick.vaultSharesTotal()
            // await vaultHealer.earnSome([poolLength-1]);
            // vaultSharesTotalAfter = await strategyMasterHealerForQuick.vaultSharesTotal()
            // expect(vaultSharesTotalAfter).greaterThan(vaultSharesTotalBefore);
        })
        
    })
})
