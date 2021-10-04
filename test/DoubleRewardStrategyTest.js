// import hre from "hardhat";

const { tokens } = require('../configs/addresses.js');
const { WMATIC, CRYSTL, DAI } = tokens.polygon;
const { expect } = require('chai');
const { ethers } = require('hardhat');
const { IUniRouter02_abi } = require('./IUniRouter02_abi.js');
const { token_abi } = require('./token_abi.js');
const { vaultHealer_abi } = require('./vaultHealer_abi.js'); //TODO - this would have to change if we change the vaulthealer
const { IWETH_abi } = require('./IWETH_abi.js');
// const { IMasterchef_abi } = require('./IMasterchef_abi.js');
const { IUniswapV2Pair_abi } = require('./IUniswapV2Pair_abi.js');

const withdrawFeeFactor = ethers.BigNumber.from(9990); //hardcoded for now - TODO change to pull from contract?
const WITHDRAW_FEE_FACTOR_MAX = ethers.BigNumber.from(10000); //hardcoded for now - TODO change to pull from contract?

//////////////////////////////////////////////////////////////////////////
// THESE FIVE VARIABLES BELOW NEED TO BE SET CORRECTLY FOR A GIVEN TEST //
//////////////////////////////////////////////////////////////////////////

const STRATEGY_CONTRACT_TYPE = 'StrategyMiniApe'; //<-- change strategy type to the contract deployed for this strategy
const { vaultSettings } = require('../configs/vaultSettings');
const { apeSwapVaults } = require('../configs/apeSwapVaults'); //<-- replace all references to 'apeSwapVaults' (for example), with the right '...Vaults' name
const DEPLOYMENT_VARS = [apeSwapVaults[0], vaultSettings.standard];
console.log(DEPLOYMENT_VARS)
console.log(apeSwapVaults[0])
const [MASTERCHEF, TACTIC, VAULT_HEALER, WANT, EARNED, PATHS, PID] = apeSwapVaults[0];
const [,,,,, TOLERANCE] = vaultSettings.standard;
const [TOKEN0_TO_EARNED_PATH,, TOKEN1_TO_EARNED_PATH] = apeSwapVaults[0].paths;
const EARNED_TOKEN_1 = EARNED[0]
const EARNED_TOKEN_2 = EARNED[1]
const minBlocksBetweenSwaps = vaultSettings.standard[8];

const TOKEN0 = ethers.utils.getAddress(TOKEN0_TO_EARNED_PATH[1]);
const TOKEN1 = ethers.utils.getAddress(TOKEN1_TO_EARNED_PATH[2]);

describe(`Testing ${STRATEGY_CONTRACT_TYPE} contract with the following variables:
    connected to vaultHealer @  ${VAULT_HEALER}
    depositing these LP tokens: ${LIQUIDITY_POOL}
    into Masterchef:            ${MASTERCHEF} 
    using Router:               ${ROUTER} 
    with earned token:          ${EARNED}
    with earned2 token:         ${EARNED2}
    Tolerance:                  ${TOLERANCE}
    `, () => {
    before(async () => {
        [owner, addr1, addr2, _] = await ethers.getSigners();
        console.log("1")
        
        console.log("3")
        // vaultHealer = await ethers.getContractAt(vaultHealer_abi, VAULT_HEALER);
        VaultHealer = await ethers.getContractFactory("VaultHealer");
        vaultHealer = await VaultHealer.deploy();
        console.log(vaultHealer.address);
        
        StrategyMasterHealer = await ethers.getContractFactory(STRATEGY_CONTRACT_TYPE, {
            libraries: {
                LibBaseStrategy: "0xc8959897D1b8CE850B494a898F402946FA80D673",
                LibPathStorage: "0x42e3b158bFd6ADc5F2734B4b5f925898bA033c0F"
              },
        });
        console.log("2")
        addresses_array = apeSwapVaults[0].addresses;
        addresses_array[0] = vaultHealer.address;
        const DEPLOYMENT_VARS = [addresses_array, vaultSettings.standard, apeSwapVaults[0].paths, apeSwapVaults[0].PID];

        strategyMasterHealer = await StrategyMasterHealer.deploy(...DEPLOYMENT_VARS);
        
        console.log("4")
        vaultHealerOwner = await vaultHealer.owner();
        console.log("5")
        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [vaultHealerOwner],
          });
        vaultHealerOwnerSigner = await ethers.getSigner(vaultHealerOwner)
        console.log("2")

        await vaultHealer.connect(vaultHealerOwnerSigner).addPool(strategyMasterHealer.address);
        console.log("3")

        await network.provider.send("hardhat_setBalance", [
            owner.address,
            "0x3635c9adc5dea00000", //amount of 1000 in hex
        ]);
        console.log("4")

        uniswapRouter = await ethers.getContractAt(IUniRouter02_abi, ROUTER);
        console.log("5")

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
        console.log("6")

    });

    describe(`Testing deployment:
    `, () => {
        // it('Should set the pid such that our want tokens correspond with the masterchef pools LP tokens', async () => {
        //     masterchef = await ethers.getContractAt(IMasterchef_abi, MASTERCHEF); 
        //     poolInfo = await masterchef.poolInfo(PID);
        //     lpToken = poolInfo[0];
        //     expect(lpToken).to.equal(ethers.utils.getAddress(LIQUIDITY_POOL));
        // })

        // it(`Should set tolerance in the range of 1-3
        // `, async () => { 
        //     expect(await strategyMasterHealer.tolerance()).to.be.within(1,3);
        // })
        //and paths too?
    })

    describe(`Testing depositing into vault, compounding vault, withdrawing from vault:
    `, () => {
        // Create LPs for the vault
        it('Should create the right LP tokens for user to deposit in the vault', async () => {
            token0 = await ethers.getContractAt(token_abi, TOKEN0);
            var token0Balance = await token0.balanceOf(owner.address);
            await token0.approve(uniswapRouter.address, token0Balance);

            token1 = await ethers.getContractAt(token_abi, TOKEN1);
            var token1Balance = await token1.balanceOf(owner.address);
            await token1.approve(uniswapRouter.address, token1Balance);

            await uniswapRouter.addLiquidity(TOKEN0, TOKEN1, token0Balance, token1Balance, 0, 0, owner.address, Date.now() + 900)
            LPtoken = await ethers.getContractAt(IUniswapV2Pair_abi, LIQUIDITY_POOL);
            initialLPtokenBalance = await LPtoken.balanceOf(owner.address);
            expect(initialLPtokenBalance).to.not.equal(0);
        })
        
        // Stake a round number of LPs (e.g., 1 or 0.0001) - not a round number yet!
        it('Should deposit users whole balance of LP tokens into the vault, increasing vaultSharesTotal by the correct amount', async () => {
            await LPtoken.approve(vaultHealer.address, initialLPtokenBalance); //no, I have to approve the vaulthealer surely?
            console.log("lp token approved")
            poolLength = await vaultHealer.poolLength()
            const LPtokenBalanceBeforeFirstDeposit = await LPtoken.balanceOf(owner.address);
            console.log("got lp token balance")
            console.log(poolLength-1);
            console.log(initialLPtokenBalance);
            await vaultHealer["deposit(uint256,uint256)"](poolLength-1,initialLPtokenBalance);
            const vaultSharesTotalAfterFirstDeposit = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            console.log("deposited lp tokens")

            expect(LPtokenBalanceBeforeFirstDeposit).to.equal(vaultSharesTotalAfterFirstDeposit); //will this work for 2nd deposit? on normal masterchef?
        })
        
        // Compound LPs (Call the earnSome function with this specific farm’s pid).
        // Check balance to ensure it increased as expected
        it('Should wait 10 blocks, then compound the LPs by calling earnSome(), so that vaultSharesTotal is greater after than before', async () => {
            const vaultSharesTotalBeforeCallingEarnSome = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            crystlToken = await ethers.getContractAt(token_abi, CRYSTL);
            daiToken = await ethers.getContractAt(token_abi, DAI);

            balanceCrystlAtBurnAddressBeforeEarn = await crystlToken.balanceOf("0x000000000000000000000000000000000000dEaD");
            balanceMaticAtUserAddressBeforeEarn = await owner.getBalance(); //maticToken.balanceOf(owner.address); //CHANGE THIS

            balanceDaiAtFeeAddressBeforeEarn = await daiToken.balanceOf("0x5386881b46C37CdD30A748f7771CF95D7B213637");
            balanceCrystlAtFeeAddressBeforeEarn = await crystlToken.balanceOf("0x5386881b46C37CdD30A748f7771CF95D7B213637");
            console.log(await ethers.provider.getBlockNumber())
            console.log(vaultSharesTotalBeforeCallingEarnSome)

            for (i=0; i<minBlocksBetweenSwaps+1;i++) {
                await ethers.provider.send("evm_mine"); //creates a delay of minBlocksBetweenSwaps+1 blocks
            }
            console.log(await ethers.provider.getBlockNumber())

            await vaultHealer.earnSome([poolLength-1]);
                        console.log(vaultSharesTotalBeforeCallingEarnSome)

            vaultSharesTotalAfterCallingEarnSome = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            console.log(vaultSharesTotalAfterCallingEarnSome)

            const differenceInVaultSharesTotal = vaultSharesTotalAfterCallingEarnSome.sub(vaultSharesTotalBeforeCallingEarnSome);

            expect(differenceInVaultSharesTotal.toNumber()).to.be.gt(0);
        })
        
        // follow the flow of funds in the transaction to ensure burn, compound fee, and LP creation are all accurate.
        it('Should burn a small amount of CRYSTL with each earn, resulting in a small increase in the CRYSTL balance of the burn address', async () => {
            const balanceCrystlAtBurnAddressAfterEarn = await crystlToken.balanceOf("0x000000000000000000000000000000000000dEaD");
            expect(balanceCrystlAtBurnAddressAfterEarn).to.be.gt(balanceCrystlAtBurnAddressBeforeEarn);
        })

        // will redesign this test once we change the payout to WMATIC - at the moment it's tricky to see the increase in user's matic balance, as they also pay out gas
        // it('Should pay a small amount of MATIC to the user with each earn, resulting in a small increase in the MATIC balance of the user', async () => {
        //     const balanceMaticAtUserAddressAfterEarn = await owner.getBalance();
        //     console.log(balanceMaticAtUserAddressBeforeEarn);
        //     console.log(balanceMaticAtUserAddressAfterEarn);
        //     expect(balanceMaticAtUserAddressAfterEarn).to.be.gt(balanceMaticAtUserAddressBeforeEarn);        
        // }) 

        it('Should pay a small amount to the rewardAddress with each earn, resulting in a small increase in CRYSTL or DAI balance of the rewardAddress', async () => {
            const balanceCrystlAtFeeAddressAfterEarn = await crystlToken.balanceOf("0x5386881b46C37CdD30A748f7771CF95D7B213637");
            const balanceDaiAtFeeAddressAfterEarn = await daiToken.balanceOf("0x5386881b46C37CdD30A748f7771CF95D7B213637");
            expect(balanceCrystlAtFeeAddressAfterEarn.add(balanceDaiAtFeeAddressAfterEarn)).to.be.gt(balanceCrystlAtFeeAddressBeforeEarn.add(balanceDaiAtFeeAddressBeforeEarn));
        })
        
        // Unstake 50% of LPs. 
        // Check transaction to ensure withdraw fee amount is as expected and amount withdrawn in as expected
        it('Should unstake 50% of LPs with correct withdraw fee amount (0.1%) and decrease users stakedWantTokens balance correctly', async () => {
            const LPtokenBalanceBeforeFirstWithdrawal = await LPtoken.balanceOf(owner.address);
            const UsersStakedTokensBeforeFirstWithdrawal = await vaultHealer.stakedWantTokens(poolLength-1, owner.address);

            await vaultHealer["withdraw(uint256,uint256)"](poolLength-1, UsersStakedTokensBeforeFirstWithdrawal.div(2)); 
            
            const LPtokenBalanceAfterFirstWithdrawal = await LPtoken.balanceOf(owner.address);
            const vaultSharesTotalAfterFirstWithdrawal = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal() 

            expect(LPtokenBalanceAfterFirstWithdrawal.sub(LPtokenBalanceBeforeFirstWithdrawal))
            .to.equal(
                (vaultSharesTotalAfterCallingEarnSome.sub(vaultSharesTotalAfterFirstWithdrawal))
                .sub((WITHDRAW_FEE_FACTOR_MAX.sub(withdrawFeeFactor)).mul(vaultSharesTotalAfterCallingEarnSome.sub(vaultSharesTotalAfterFirstWithdrawal)).div(WITHDRAW_FEE_FACTOR_MAX))
                );
        })
        
        // Deposit 100% of users LP tokens into vault, ensure balance increases as expected.
        it('Should accurately increase vaultSharesTotal upon second deposit', async () => {
            await LPtoken.approve(vaultHealer.address, initialLPtokenBalance);
            const LPtokenBalanceBeforeSecondDeposit = await LPtoken.balanceOf(owner.address);
            const vaultSharesTotalBeforeSecondDeposit = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0

            await vaultHealer["deposit(uint256,uint256)"](poolLength-1, LPtokenBalanceBeforeSecondDeposit); //owner (default signer) deposits LP tokens into specified pid vaulthealer
            
            const LPtokenBalanceAfterSecondDeposit = await LPtoken.balanceOf(owner.address);
            const vaultSharesTotalAfterSecondDeposit = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0;

            expect(LPtokenBalanceBeforeSecondDeposit.sub(LPtokenBalanceAfterSecondDeposit)).to.equal(vaultSharesTotalAfterSecondDeposit.sub(vaultSharesTotalBeforeSecondDeposit)); //will this work for 2nd deposit? on normal masterchef?
        })
        
        // Withdraw 100%
        it('Should withdraw remaining balance back to owner, minus withdrawal fee (0.1%)', async () => {
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
            console.log(await crystlToken.balanceOf(strategyMasterHealer.address))
            expect(UsersStakedTokensAfterFinalWithdrawal.toNumber()).to.equal(0);
        })
        
    })
})
