// import hre from "hardhat";

const { tokens } = require('../configs/addresses.js');
const { WMATIC } = tokens.polygon;
const { expect, assert } = require('chai');
const { ethers } = require('hardhat');
const { IUniRouter02_abi } = require('./IUniRouter02_abi.js');
const { token_abi } = require('./token_abi.js');
const { vaultHealer_abi } = require('./vaultHealer_abi.js'); //TODO - this would have to change if we change the vaulthealer
const { IWETH_abi } = require('./IWETH_abi.js');

const withdrawFeeFactor = 9990; //hardcoded for now - TODO change to pull from contract?
const WITHDRAW_FEE_FACTOR_MAX = 10000; //hardcoded for now - TODO change to pull from contract?

//////////////////////////////////////////////////////////////////////////
// THESE FIVE VARIABLES BELOW NEED TO BE SET CORRECTLY FOR A GIVEN TEST //
//////////////////////////////////////////////////////////////////////////

const STRATEGY_CONTRACT_TYPE = 'StrategyMasterHealer'; //<-- change strategy type to the contract deployed for this strategy
const { takoDefiVaults } = require('../configs/takoDefiVaults'); //<-- replace all references to 'takoDefiVaults' (for example), with the right '...Vaults' name
const DEPLOYMENT_VARS = [takoDefiVaults[0].addresses, ...takoDefiVaults[0].strategyConfig];
const [VAULT_HEALER, MASTERCHEF, ROUTER, LIQUIDITY_POOL, EARNED] = takoDefiVaults[0].addresses
const [PID, TOLERANCE,,,,,,TOKEN0_TO_EARNED_PATH, TOKEN1_TO_EARNED_PATH] = takoDefiVaults[0].strategyConfig;

const TOKEN0 = ethers.utils.getAddress(TOKEN0_TO_EARNED_PATH[0]);
const TOKEN1 = ethers.utils.getAddress(TOKEN1_TO_EARNED_PATH[0]);

describe('StrategyMasterHealer contract', () => {
    // let StrategyMasterHealer, strategyMasterHealer, owner, addr1, addr2;

    before(async () => {
        [owner, addr1, addr2, _] = await ethers.getSigners();

        StrategyMasterHealer = await ethers.getContractFactory(STRATEGY_CONTRACT_TYPE); //<-- this needs to change for different tests!!
        strategyMasterHealer = await StrategyMasterHealer.deploy(...DEPLOYMENT_VARS);

        vaultHealer = await ethers.getContractAt(vaultHealer_abi, VAULT_HEALER);
        vaultHealerOwner = await vaultHealer.owner();
        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [vaultHealerOwner],
          });
        vaultHealerOwnerSigner = await ethers.getSigner(vaultHealerOwner)

        await vaultHealer.connect(vaultHealerOwnerSigner).addPool(strategyMasterHealer.address);
        
        await network.provider.send("hardhat_setBalance", [
            owner.address,
            "0x3635c9adc5dea00000", //amount of 1000 in hex
        ]);

        uniswapRouter = await ethers.getContractAt(IUniRouter02_abi, ROUTER);

        if (TOKEN0 == ethers.utils.getAddress(WMATIC) ){
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN0); 
            await wmatic_token.deposit({ value: ethers.utils.parseEther("100") });
        } else {
            await uniswapRouter.swapExactETHForTokens(0, [WMATIC, TOKEN0], owner.address, Date.now() + 900, { value: ethers.utils.parseEther("100") })
        }
        if (TOKEN1 == ethers.utils.getAddress(WMATIC)) {
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN1); 
            await wmatic_token.deposit({ value: ethers.utils.parseEther("100") });
        } else {
            await uniswapRouter.swapExactETHForTokens(0, [WMATIC, TOKEN1], owner.address, Date.now() + 900, { value: ethers.utils.parseEther("100") })
        }
    });

    describe('Deployment', () => {
        it('Should set the right VaultHealer address - PRODUCTION_VAULT_HEALER', async () => {
            expect(await strategyMasterHealer.vaultChefAddress()).to.equal(ethers.utils.getAddress(VAULT_HEALER)); //getAddress ensures that address is checksummed
        })

        it('Should set the right Masterchef address', async () => {
            expect(await strategyMasterHealer.masterchefAddress()).to.equal(ethers.utils.getAddress(MASTERCHEF));
        })

        it('Should set the right Router address', async () => {
            expect(await strategyMasterHealer.uniRouterAddress()).to.equal(ethers.utils.getAddress(ROUTER));
        })

        it('Should set the right LP address', async () => {
            expect(await strategyMasterHealer.wantAddress()).to.equal(ethers.utils.getAddress(LIQUIDITY_POOL));
        })

        it('Should set the right Reward/Earned address', async () => {
            expect(await strategyMasterHealer.earnedAddress()).to.equal(ethers.utils.getAddress(EARNED));
        })

        it('Should set the right pid for the eventual farm it gets vaulted in', async () => {
            expect(await strategyMasterHealer.pid()).to.equal(PID);
        })

        it('Should set the right tolerance', async () => { //could do a less than 3 check here?
            expect(await strategyMasterHealer.tolerance()).to.equal(TOLERANCE);
        })
        //and paths too?
    })

    describe('Transactions', () => {
        // Create LPs for the vault
        it('Should create the right LP tokens for user to deposit in the vault', async () => {
            token0 = await ethers.getContractAt(token_abi, TOKEN0);
            var token0Balance = await token0.balanceOf(owner.address);
            await token0.approve(uniswapRouter.address, token0Balance);

            token1 = await ethers.getContractAt(token_abi, TOKEN1);
            var token1Balance = await token1.balanceOf(owner.address);
            await token1.approve(uniswapRouter.address, token1Balance);

            await uniswapRouter.addLiquidity(TOKEN0, TOKEN1, token0Balance, token1Balance, 0, 0, owner.address, Date.now() + 900)
            LPtoken = await ethers.getContractAt(token_abi, LIQUIDITY_POOL);
            LPtokenBalance = await LPtoken.balanceOf(owner.address);

            expect(LPtokenBalance).to.not.equal(0);
        })
        
        // Stake a round number of LPs (e.g., 1 or 0.0001) - not a round number yet!
        it('Should deposit users whole balance of LP tokens into the vault, increasing vaultSharesTotal by the correct amount', async () => {
            await LPtoken.approve(vaultHealer.address, LPtokenBalance); //no, I have to approve the vaulthealer surely?
            
            poolLength = await vaultHealer.poolLength()
            LPtokenBalanceBefore = await LPtoken.balanceOf(owner.address);
            
            await vaultHealer["deposit(uint256,uint256)"](poolLength-1,LPtokenBalance); //owner (default signer) deposits 1 of LP tokens into pid 0 of vaulthealer
            vaultSharesTotalAfter = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            
            expect(LPtokenBalanceBefore).to.equal(vaultSharesTotalAfter); //will this work for 2nd deposit? on normal masterchef?
        })
        
        // Compound LPs (Call the earnSome function with this specific farm’s pid).
        // Check balance to ensure it increased as expected
        it('Should compound the LPs upon calling earnSome(), so that vaultSharesTotal is greater after than before', async () => {
            vaultSharesTotalBefore = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            
            await vaultHealer.earnSome([poolLength-1]);
            
            vaultSharesTotalAfter = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            
            differenceInVaultSharesTotal = vaultSharesTotalAfter - vaultSharesTotalBefore;
            expect(differenceInVaultSharesTotal).to.be.gt(0);
            // assert.isAbove(vaultSharesTotalAfter.toNumber(), vaultSharesTotalBefore.toNumber(), "Vault Shares go up after compounding");
        })
        
        // follow the flow of funds in the transaction to ensure burn, compound fee, and LP creation are all accurate.
        it('Should burn x amount of crystal with each earn, pay y fee to compound, and create z LPs when it compounds', async () => {
            // what to put here? a little tricky...
        })
        
        // Unstake 50% of LPs. 
        // Check transaction to ensure withdraw fee amount is as expected and amount withdrawn in as expected
        it('Should unstake 50% of LPs with correct withdraw fee amount (0.1%) and decrease users stakedWantTokens balance correctly', async () => {
            LPtokenBalanceBefore = await LPtoken.balanceOf(owner.address);
            UsersStakedTokensBefore = await vaultHealer.stakedWantTokens(poolLength-1, owner.address);
            
            await vaultHealer["withdraw(uint256,uint256)"](poolLength-1, UsersStakedTokensBefore.div(2)); //owner (default signer) deposits 1 of LP tokens into pid 0 of vaulthealer
            
            LPtokenBalanceAfter = await LPtoken.balanceOf(owner.address);
            UsersStakedTokensAfter = await vaultHealer.stakedWantTokens(poolLength-1, owner.address);

            expect(LPtokenBalanceAfter-LPtokenBalanceBefore)
            .to.equal(
                (UsersStakedTokensBefore-UsersStakedTokensAfter)
                -parseInt((WITHDRAW_FEE_FACTOR_MAX - withdrawFeeFactor)/WITHDRAW_FEE_FACTOR_MAX*(UsersStakedTokensBefore-UsersStakedTokensAfter))
                );
        })
        
        // Deposit 100% of users LP tokens into vault, ensure balance increases as expected.
        it('Should accurately increase vaultSharesTotal upon second deposit', async () => {
            await LPtoken.approve(vaultHealer.address, LPtokenBalance);
            LPtokenBalanceBefore = await LPtoken.balanceOf(owner.address);
            vaultSharesTotalBefore = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0

            await vaultHealer["deposit(uint256,uint256)"](poolLength-1, LPtokenBalanceBefore); //owner (default signer) deposits LP tokens into specified pid vaulthealer
            
            LPtokenBalanceAfter = await LPtoken.balanceOf(owner.address);
            vaultSharesTotalAfter = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            
            expect(LPtokenBalanceBefore-LPtokenBalanceAfter).to.equal(vaultSharesTotalAfter-vaultSharesTotalBefore); //will this work for 2nd deposit? on normal masterchef?
        })
        
        // Withdraw 100%
        it('Should withdraw remaining balance back to owner, minus withdrawal fee (0.1%)', async () => {
            LPtokenBalanceBefore = await LPtoken.balanceOf(owner.address);
            UsersStakedTokensBefore = await vaultHealer.stakedWantTokens(poolLength-1, owner.address);

            await vaultHealer["withdraw(uint256,uint256)"](poolLength-1, UsersStakedTokensBefore); //owner (default signer) deposits 1 of LP tokens into pid 0 of vaulthealer
            
            LPtokenBalanceAfter = await LPtoken.balanceOf(owner.address);
            UsersStakedTokensAfter = await vaultHealer.stakedWantTokens(poolLength-1, owner.address);
            console.log(LPtokenBalanceBefore, LPtokenBalanceAfter, UsersStakedTokensAfter, UsersStakedTokensBefore)
            
            expect(UsersStakedTokensBefore
                -LPtokenBalanceAfter
                -parseInt((WITHDRAW_FEE_FACTOR_MAX - withdrawFeeFactor)*UsersStakedTokensBefore/WITHDRAW_FEE_FACTOR_MAX))
                .to.equal(0);
        })

        //ensure no funds left in the vault.
        it('Should leave zero funds in vault after 100% withdrawal', async () => {
            expect(UsersStakedTokensAfter.toNumber()).to.equal(0);
        })
        
    })
})
