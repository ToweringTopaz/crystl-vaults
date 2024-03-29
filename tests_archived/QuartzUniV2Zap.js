// import hre from "hardhat";

const { tokens } = require('../configs/addresses.js');
const { WMATIC, CRYSTL } = tokens.polygon;
const { expect, assert } = require('chai');
const { ethers } = require('hardhat');
const { IUniRouter02_abi } = require('./abi_files/IUniRouter02_abi.js');
const { token_abi } = require('./abi_files/token_abi.js');
const { vaultHealer_abi } = require('./abi_files/vaultHealer_abi.js'); //TODO - this would have to change if we change the vaulthealer
const { IWETH_abi } = require('./abi_files/IWETH_abi.js');

const withdrawFeeFactor = ethers.BigNumber.from(9990); //hardcoded for now - TODO change to pull from contract?
const WITHDRAW_FEE_FACTOR_MAX = ethers.BigNumber.from(10000); //hardcoded for now - TODO change to pull from contract?

//////////////////////////////////////////////////////////////////////////
// THESE FIVE VARIABLES BELOW NEED TO BE SET CORRECTLY FOR A GIVEN TEST //
//////////////////////////////////////////////////////////////////////////

const STRATEGY_CONTRACT_TYPE = 'StrategyMiniApe'; //<-- change strategy type to the contract deployed for this strategy
const { apeSwapVaults } = require('../configs/apeSwapVaults'); //<-- replace all references to 'apeSwapVaults' (for example), with the right '...Vaults' name
const DEPLOYMENT_VARS = [
    apeSwapVaults[1]['want'],
    vaultHealer.address,
    apeSwapVaults[1]['masterchef'],
    apeSwapVaults[1]['tactic'],
    apeSwapVaults[1]['PID'],
    vaultSettings.standard,
    apeSwapVaults[1]['earned'],
    ];
const [VAULT_HEALER, MASTERCHEF, ROUTER, LIQUIDITY_POOL, EARNED] = apeSwapVaults[4].addresses
const [PID, TOLERANCE,,,,,,TOKEN0_TO_EARNED_PATH, TOKEN1_TO_EARNED_PATH] = apeSwapVaults[4].strategyConfig;

const TOKEN0 = ethers.utils.getAddress(TOKEN0_TO_EARNED_PATH[0]);
const TOKEN1 = ethers.utils.getAddress(TOKEN1_TO_EARNED_PATH[0]);
const TOKEN_OTHER = CRYSTL;

describe('StrategyMasterHealer contract', () => {
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
        
        QuartzUniV2Zap = await ethers.getContractFactory('QuartzUniV2Zap'); //<-- this needs to change for different tests!!
        quartzUniV2Zap = await QuartzUniV2Zap.deploy(vaultHealer.address);

        await network.provider.send("hardhat_setBalance", [
            owner.address,
            "0x21E19E0C9BAB2400000", //amount of 1000 in hex
        ]);

        uniswapRouter = await ethers.getContractAt(IUniRouter02_abi, ROUTER);

        if (TOKEN0 == ethers.utils.getAddress(WMATIC) ){
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN0); 
            await wmatic_token.deposit({ value: ethers.utils.parseEther("3000") });
        } else {
            await uniswapRouter.swapExactETHForTokens(0, [WMATIC, TOKEN0], owner.address, Date.now() + 900, { value: ethers.utils.parseEther("3000") })
        }
        if (TOKEN1 == ethers.utils.getAddress(WMATIC)) {
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN1); 
            await wmatic_token.deposit({ value: ethers.utils.parseEther("3000") });
        } else {
            await uniswapRouter.swapExactETHForTokens(0, [WMATIC, TOKEN1], owner.address, Date.now() + 900, { value: ethers.utils.parseEther("3000") })
        }

        await uniswapRouter.swapExactETHForTokens(0, [WMATIC, TOKEN_OTHER], owner.address, Date.now() + 900, { value: ethers.utils.parseEther("3000") })
    });

    describe('Transactions', () => {
        it('Should zap token0 into the vault (convert to underlying, add liquidity, and stake)', async () => {
            token0 = await ethers.getContractAt(token_abi, TOKEN0);
            var token0Balance = await token0.balanceOf(owner.address);
            await token0.approve(quartzUniV2Zap.address, token0Balance);
            
            const vaultSharesTotalBeforeFirstZap = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            poolLength = await vaultHealer.poolLength()

            await quartzUniV2Zap.quartzIn(poolLength-1, 0, token0.address, token0Balance); //To Do - change min in amount from 0
            
            const vaultSharesTotalAfterFirstZap = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0

            expect(vaultSharesTotalAfterFirstZap).to.be.gt(vaultSharesTotalBeforeFirstZap); //will this work for 2nd Zap? on normal masterchef?
        })
        
        it('Should zap token1 into the vault (convert to underlying, add liquidity, and stake)', async () => {
            token1 = await ethers.getContractAt(token_abi, TOKEN1);
            var token1Balance = await token1.balanceOf(owner.address);
            await token1.approve(quartzUniV2Zap.address, token1Balance);
            
            const vaultSharesTotalBeforeFirstZap = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            poolLength = await vaultHealer.poolLength()

            await quartzUniV2Zap.quartzIn(poolLength-1, 0, token1.address, token1Balance); //To Do - change min in amount from 0
            
            const vaultSharesTotalAfterFirstZap = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0

            expect(vaultSharesTotalAfterFirstZap).to.be.gt(vaultSharesTotalBeforeFirstZap); //will this work for 2nd Zap? on normal masterchef?
        })

        it('Should zap a token that is neither token0 nor token1 into the vault (convert to underlying, add liquidity, and stake)', async () => {
            // assume(TOKEN_OTHER != TOKEN0 && TOKEN_OTHER != TOKEN1);
            tokenOther = await ethers.getContractAt(token_abi, TOKEN_OTHER);
            var tokenOtherBalance = await tokenOther.balanceOf(owner.address);
            await tokenOther.approve(quartzUniV2Zap.address, tokenOtherBalance);
            
            const vaultSharesTotalBeforeFirstZap = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            poolLength = await vaultHealer.poolLength()

            await quartzUniV2Zap.quartzIn(poolLength-1, 0, tokenOther.address, tokenOtherBalance); //To Do - change min in amount from 0
            
            const vaultSharesTotalAfterFirstZap = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0

            expect(vaultSharesTotalAfterFirstZap).to.be.gt(vaultSharesTotalBeforeFirstZap); //will this work for 2nd Zap? on normal masterchef?
        })

        // Withdraw 100%
        it('Should withdraw remaining balance back to owner, minus withdrawal fee (0.1%)', async () => {
            LPtoken = await ethers.getContractAt(token_abi, LIQUIDITY_POOL);
            const LPtokenBalanceBeforeFinalWithdrawal = await LPtoken.balanceOf(owner.address);
            const UsersStakedTokensBeforeFinalWithdrawal = await vaultHealer.stakedWantTokens(poolLength-1, owner.address);

            await vaultHealer["withdraw(uint256,uint256)"](poolLength-1, UsersStakedTokensBeforeFinalWithdrawal); //owner (default signer) deposits 1 of LP tokens into pid 0 of vaulthealer
            
            const LPtokenBalanceAfterFinalWithdrawal = await LPtoken.balanceOf(owner.address);
            UsersStakedTokensAfterFinalWithdrawal = await vaultHealer.stakedWantTokens(poolLength-1, owner.address);

            expect(LPtokenBalanceAfterFinalWithdrawal.sub(LPtokenBalanceBeforeFinalWithdrawal))
            .to.equal(
                (UsersStakedTokensBeforeFinalWithdrawal.sub(UsersStakedTokensAfterFinalWithdrawal))
                .sub(
                    (WITHDRAW_FEE_FACTOR_MAX.sub(withdrawFeeFactor))
                    .mul(UsersStakedTokensBeforeFinalWithdrawal.sub(UsersStakedTokensAfterFinalWithdrawal))
                    .div(WITHDRAW_FEE_FACTOR_MAX)
                ));
        })

        //ensure no funds left in the vault.
        it('Should leave zero funds in vault after 100% withdrawal', async () => {
            expect(UsersStakedTokensAfterFinalWithdrawal.toNumber()).to.equal(0);
        })

        it('Zap out should convert LP tokens back to underlying tokens, leaving a zero balance of LP tokens', async () => {
            const LPtokenBalanceBeforeZapOut = await LPtoken.balanceOf(owner.address);
            await LPtoken.approve(quartzUniV2Zap.address, LPtokenBalanceBeforeZapOut);
            
            await quartzUniV2Zap.quartzOut(poolLength-1, LPtokenBalanceBeforeZapOut); 
            
            const LPtokenBalanceAfterZapOut = await LPtoken.balanceOf(owner.address);

            expect(LPtokenBalanceAfterZapOut.toNumber()).to.equal(0);
        })

        // it('Leave user with a balance of token0 and token1', async () => {
        //     LPtoken = await ethers.getContractAt(token_abi, LIQUIDITY_POOL);
        //     const LPtokenBalanceBeforeZapOut = await LPtoken.balanceOf(owner.address);
            
        //     await quartzUniV2Zap.quartzOut(poolLength-1, LPtokenBalanceBeforeZapOut); 
            
        //     const LPtokenBalanceAfterZapOut = await LPtoken.balanceOf(owner.address);

        //     expect(LPtokenBalanceAfterZapOut.toNumber()).to.equal(0);
        // })
        
    })
})
