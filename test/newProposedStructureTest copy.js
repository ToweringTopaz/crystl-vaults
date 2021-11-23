// import hre from "hardhat";

const { tokens, accounts } = require('../configs/addresses.js');
const { WMATIC, CRYSTL, DAI } = tokens.polygon;
const { FEE_ADDRESS, BURN_ADDRESS, ZERO_ADDRESS } = accounts.polygon;
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

const STRATEGY_CONTRACT_TYPE = 'StrategyVHStandard'; //<-- change strategy type to the contract deployed for this strategy
const { vaultSettings } = require('../configs/vaultSettings');
const { apeSwapVaults } = require('../configs/apeSwapVaults'); //<-- replace all references to 'apeSwapVaults' (for example), with the right '...Vaults' name
const MASTERCHEF = apeSwapVaults[0].masterchef;
const TACTIC = apeSwapVaults[0].tactic;
const VAULT_HEALER = apeSwapVaults[0].vaulthealer;
const WANT = apeSwapVaults[0].want;
const EARNED = apeSwapVaults[0].earned;
const PATHS = apeSwapVaults[0].paths;
const PID = apeSwapVaults[0].PID;
const ROUTER = vaultSettings.standard[0];

const TOLERANCE = vaultSettings.standard[9];

// const [TOKEN0_TO_EARNED_PATH,, TOKEN1_TO_EARNED_PATH] = apeSwapVaults[0].paths;
const EARNED_TOKEN_1 = EARNED[0]
const EARNED_TOKEN_2 = EARNED[1]
const minBlocksBetweenSwaps = vaultSettings.standard[12];

describe(`Testing ${STRATEGY_CONTRACT_TYPE} contract with the following variables:
    connected to vaultHealer @  ${VAULT_HEALER}
    depositing these LP tokens: ${WANT}
    into Masterchef:            ${MASTERCHEF} 
    with earned token:          ${EARNED_TOKEN_1}
    with earned2 token:         ${EARNED_TOKEN_2}
    Tolerance:                  ${TOLERANCE}
    `, () => {
    before(async () => {
        [user1, user2, user3, _] = await ethers.getSigners();
        
        // vaultHealer = await ethers.getContractAt(vaultHealer_abi, VAULT_HEALER);
        VaultHealer = await ethers.getContractFactory("VaultHealer", {
            // libraries: {
            //     LibMagnetite: "0xf34b0c8ab719dED106D6253798D3ed5c7fCA2E04",
            //     LibVaultConfig: "0x95Fe76f0BA650e7C3a3E1Bb6e6DFa0e8bA28fd6d"
            //   },
        });
        const feeConfig = 
            [
            // withdraw fee: token is not set here; standard fee address; 10 now means 0.1% consistent with other fees
                [ ZERO_ADDRESS, FEE_ADDRESS, 10 ],
                [ WMATIC, FEE_ADDRESS, 50 ], //earn fee: wmatic is paid; receiver is ignored; 0.5% rate
                [ DAI, FEE_ADDRESS, 50 ], //reward fee: paid in DAI; standard fee address; 0.5% rate
                [ CRYSTL, BURN_ADDRESS, 400 ] //burn fee: crystl to burn address; 4% rate
            ]
        
        vaultHealer = await VaultHealer.deploy(feeConfig, 10);
        // console.log(vaultHealer.address);
        
        StrategyMasterHealer = await ethers.getContractFactory(STRATEGY_CONTRACT_TYPE, {
            // libraries: {
            //     LibVaultSwaps: "0x1B20Dab7BE777a9CFC363118BC46f7905A7628a1",
            //     LibVaultConfig: "0x95Fe76f0BA650e7C3a3E1Bb6e6DFa0e8bA28fd6d"
            //   },
        });        
        const DEPLOYMENT_VARS = [
            apeSwapVaults[0]['want'],
            vaultHealer.address,
            apeSwapVaults[0]['masterchef'],
            apeSwapVaults[0]['tactic'],
            apeSwapVaults[0]['PID'],
            vaultSettings.standard,
            apeSwapVaults[0]['earned'],
            ];

        strategyMasterHealer = await StrategyMasterHealer.deploy(...DEPLOYMENT_VARS);
        // TOKEN0 = await strategyMasterHealer.lpToken[0];
        // TOKEN1 = await strategyMasterHealer.lpToken[1];
        // console.log(await strategyMasterHealer.lpToken)
        LPtoken = await ethers.getContractAt(IUniswapV2Pair_abi, WANT);
        TOKEN0 = await LPtoken.token0()
        TOKEN1 = await LPtoken.token1()

        vaultHealerOwner = await vaultHealer.owner();

        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [vaultHealerOwner],
          });
        vaultHealerOwnerSigner = await ethers.getSigner(vaultHealerOwner)

        await vaultHealer.connect(vaultHealerOwnerSigner).addPool(strategyMasterHealer.address);
        pid = await vaultHealer.poolLength() -1;

        await network.provider.send("hardhat_setBalance", [
            user1.address,
            "0x21E19E0C9BAB2400000", //amount of 1000 in hex
        ]);

        await network.provider.send("hardhat_setBalance", [
            user2.address,
            "0x21E19E0C9BAB2400000", //amount of 1000 in hex
        ]);

        uniswapRouter = await ethers.getContractAt(IUniRouter02_abi, ROUTER);

        if (TOKEN0 == ethers.utils.getAddress(WMATIC) ){
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN0); 
            await wmatic_token.deposit({ value: ethers.utils.parseEther("4500") });
        } else {
            await uniswapRouter.swapExactETHForTokens(0, [WMATIC, TOKEN0], user1.address, Date.now() + 900, { value: ethers.utils.parseEther("4500") })
        }
        if (TOKEN1 == ethers.utils.getAddress(WMATIC)) {
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN1); 
            await wmatic_token.deposit({ value: ethers.utils.parseEther("4500") });
        } else {
            await uniswapRouter.swapExactETHForTokens(0, [WMATIC, TOKEN1], user1.address, Date.now() + 900, { value: ethers.utils.parseEther("4500") })
        }

        if (TOKEN0 == ethers.utils.getAddress(WMATIC) ){
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN0); 
            await wmatic_token.connect(user2).deposit({ value: ethers.utils.parseEther("4500") });
        } else {
            await uniswapRouter.connect(user2).swapExactETHForTokens(0, [WMATIC, TOKEN0], user2.address, Date.now() + 900, { value: ethers.utils.parseEther("4500") })
        }
        if (TOKEN1 == ethers.utils.getAddress(WMATIC)) {
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN1); 
            await wmatic_token.connect(user2).deposit({ value: ethers.utils.parseEther("4500") });
        } else {
            await uniswapRouter.connect(user2).swapExactETHForTokens(0, [WMATIC, TOKEN1], user2.address, Date.now() + 900, { value: ethers.utils.parseEther("4500") })
        }

        //create the staking pool for the boosted vault
        StakingPool = await ethers.getContractFactory("StakingPool", {});
        //need the wantToken address from the strategy!
        stakingPool = await StakingPool.deploy(
            vaultHealer.address, //and what about the pid? yes, the stakingPool needs it!, right up front...
            pid, //I'm hardcoding this for now - how can we do it in future??
            "0x76bf0c28e604cc3fe9967c83b3c3f31c213cfe64", 
            1000000, //is this in WEI? assume so...
            21131210, //this is the block we're currently forking from - WATCH OUT if we change forking block
            21771725 //also watch out that we don't go past this, but we shouldn't
        )
        //fund the staking pool with reward token, Crystl 
        await uniswapRouter.swapExactETHForTokens(0, [WMATIC, CRYSTL], stakingPool.address, Date.now() + 900, { value: ethers.utils.parseEther("45") })

    });

    describe(`Testing depositing into vault, compounding vault, withdrawing from vault:
    `, () => {
        // Create LPs for the vault
        it('Should create the right LP tokens for users to deposit in the vault', async () => {
            token0 = await ethers.getContractAt(token_abi, TOKEN0);
            var token0Balance = await token0.balanceOf(user1.address);
            await token0.approve(uniswapRouter.address, token0Balance);

            var token0BalanceUser2 = await token0.balanceOf(user2.address);
            await token0.connect(user2).approve(uniswapRouter.address, token0BalanceUser2);

            token1 = await ethers.getContractAt(token_abi, TOKEN1);
            var token1Balance = await token1.balanceOf(user1.address);
            await token1.approve(uniswapRouter.address, token1Balance);

            var token1BalanceUser2 = await token1.balanceOf(user2.address);
            await token1.connect(user2).approve(uniswapRouter.address, token1BalanceUser2);

            await uniswapRouter.addLiquidity(TOKEN0, TOKEN1, token0Balance, token1Balance, 0, 0, user1.address, Date.now() + 900)
            await uniswapRouter.connect(user2).addLiquidity(TOKEN0, TOKEN1, token0BalanceUser2, token1BalanceUser2, 0, 0, user2.address, Date.now() + 900)

            // LPtoken = await ethers.getContractAt(IUniswapV2Pair_abi, WANT);
            initialLPtokenBalance = await LPtoken.balanceOf(user1.address);
            expect(initialLPtokenBalance).to.not.equal(0);
        })
        
        // Stake a round number of LPs (e.g., 1 or 0.0001) - not a round number yet!
        it('Should deposit user1\'s whole balance of LP tokens into the vault, increasing vaultSharesTotal by the correct amount', async () => {
            await LPtoken.approve(vaultHealer.address, initialLPtokenBalance); //no, I have to approve the vaulthealer surely?
            const LPtokenBalanceBeforeFirstDeposit = await LPtoken.balanceOf(user1.address);
            await vaultHealer["deposit(uint256,uint256)"](pid,initialLPtokenBalance);
            const vaultSharesTotalAfterFirstDeposit = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            console.log(`deposited ${ethers.utils.formatEther(vaultSharesTotalAfterFirstDeposit)} lp tokens`)

            expect(LPtokenBalanceBeforeFirstDeposit).to.equal(vaultSharesTotalAfterFirstDeposit); //will this work for 2nd deposit? on normal masterchef?
        })
        
        it('Should mint ERC1155 tokens for the user, with the pid of the strategy', async () => {
            userBalanceOfStrategyTokens = await vaultHealer.balanceOf(user1.address, pid);
            expect(userBalanceOfStrategyTokens).to.be.gt("0") //equal(vaultSharesTotalAfterFirstDeposit); 
        })

        it('Should allow user to stake those tokens in the stakingPool, showing a balanceOf in the pool afterwards', async () => {
            userBalanceOfStrategyTokensBeforeStaking = await vaultHealer.balanceOf(user1.address, pid);
            //need to do approval first?
            await vaultHealer.connect(user1).setApprovalForAll(stakingPool.address, true); //dangerous to approve all forever?

            await stakingPool.connect(user1).deposit(userBalanceOfStrategyTokensBeforeStaking);
            user = await stakingPool.userInfo(user1.address);
            userBalanceOfStakingPool = user.amount;
            expect(userBalanceOfStakingPool).to.equal(userBalanceOfStrategyTokensBeforeStaking); //will only be true on first deposit?
        })

        it('Should accumulate rewards for the staked user over time', async () => {
            userRewardDebtAtStart = await stakingPool.pendingReward(user1.address);

            for (i=0; i<100;i++) { //minBlocksBetweenSwaps
                await ethers.provider.send("evm_mine"); //creates a delay of minBlocksBetweenSwaps+1 blocks
                }
            
            userRewardDebtAfterTime = await stakingPool.pendingReward(user1.address);;
            expect(userRewardDebtAfterTime).to.be.gt(userRewardDebtAtStart); //will only be true on first deposit?
        })

        it('Should should allow the user to unstake their receipt tokens', async () => {
            user = await stakingPool.userInfo(user1.address);
            userBalanceOfStakingPoolBeforeWithdrawal = user.amount;

            await stakingPool.connect(user1).withdraw(userBalanceOfStakingPool);

            user = await stakingPool.userInfo(user1.address);
            userBalanceOfStakingPoolAfterWithdrawal = user.amount;
            
            expect(userBalanceOfStakingPoolBeforeWithdrawal).to.be.gt(userBalanceOfStakingPoolAfterWithdrawal); //will only be true on first deposit?
        })

        // Compound LPs (Call the earnSome function with this specific farm’s pid).
        // Check balance to ensure it increased as expected
        it('Should wait 10 blocks, then compound the LPs by calling earnSome(), so that vaultSharesTotal is greater after than before', async () => {
            const vaultSharesTotalBeforeCallingEarnSome = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            crystlToken = await ethers.getContractAt(token_abi, CRYSTL);
            daiToken = await ethers.getContractAt(token_abi, DAI);

            balanceCrystlAtBurnAddressBeforeEarn = await crystlToken.balanceOf("0x000000000000000000000000000000000000dEaD");
            balanceMaticAtUserAddressBeforeEarn = await user1.getBalance(); //maticToken.balanceOf(user1.address); //CHANGE THIS

            balanceDaiAtFeeAddressBeforeEarn = await daiToken.balanceOf("0x5386881b46C37CdD30A748f7771CF95D7B213637");
            balanceCrystlAtFeeAddressBeforeEarn = await crystlToken.balanceOf("0x5386881b46C37CdD30A748f7771CF95D7B213637");
            console.log(`Block number before calling earn ${await ethers.provider.getBlockNumber()}`)
            console.log(`vaultSharesTotalBeforeCallingEarnSome: ${vaultSharesTotalBeforeCallingEarnSome}`)

            for (i=0; i<1000;i++) { //minBlocksBetweenSwaps
                await ethers.provider.send("evm_mine"); //creates a delay of minBlocksBetweenSwaps+1 blocks
            }

            await vaultHealer.earnSome([pid]);
            console.log(`Block number after calling earn ${await ethers.provider.getBlockNumber()}`)

            vaultSharesTotalAfterCallingEarnSome = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            console.log(`vaultSharesTotalAfterCallingEarnSome: ${vaultSharesTotalAfterCallingEarnSome}`)

            const differenceInVaultSharesTotal = vaultSharesTotalAfterCallingEarnSome.sub(vaultSharesTotalBeforeCallingEarnSome);

            expect(differenceInVaultSharesTotal).to.be.gt(0); //.toNumber()
        })
        
        // follow the flow of funds in the transaction to ensure burn, compound fee, and LP creation are all accurate.
        it('Should burn a small amount of CRYSTL with each earn, resulting in a small increase in the CRYSTL balance of the burn address', async () => {
            const balanceCrystlAtBurnAddressAfterEarn = await crystlToken.balanceOf("0x000000000000000000000000000000000000dEaD");
            expect(balanceCrystlAtBurnAddressAfterEarn).to.be.gt(balanceCrystlAtBurnAddressBeforeEarn);
        })

        // will redesign this test once we change the payout to WMATIC - at the moment it's tricky to see the increase in user's matic balance, as they also pay out gas
        // it('Should pay a small amount of MATIC to the user with each earn, resulting in a small increase in the MATIC balance of the user', async () => {
        //     const balanceMaticAtUserAddressAfterEarn = await user1.getBalance();
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
            const LPtokenBalanceBeforeFirstWithdrawal = await LPtoken.balanceOf(user1.address);
            const UsersStakedTokensBeforeFirstWithdrawal = await vaultHealer.stakedWantTokens(pid, user1.address);

            await vaultHealer["withdraw(uint256,uint256)"](pid, UsersStakedTokensBeforeFirstWithdrawal.div(2)); 
            
            const LPtokenBalanceAfterFirstWithdrawal = await LPtoken.balanceOf(user1.address);
            vaultSharesTotalAfterFirstWithdrawal = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal() 

            expect(LPtokenBalanceAfterFirstWithdrawal.sub(LPtokenBalanceBeforeFirstWithdrawal))
            .to.equal(
                (vaultSharesTotalAfterCallingEarnSome.sub(vaultSharesTotalAfterFirstWithdrawal))
                // .sub((WITHDRAW_FEE_FACTOR_MAX.sub(withdrawFeeFactor))
                // .mul(vaultSharesTotalAfterCallingEarnSome.sub(vaultSharesTotalAfterFirstWithdrawal))
                // .div(WITHDRAW_FEE_FACTOR_MAX))
                )
                ;
        })
        // Stake a round number of LPs (e.g., 1 or 0.0001) - not a round number yet!
        it('Should deposit user2\'s whole balance of LP tokens into the vault, increasing vaultSharesTotal by the correct amount', async () => {
            const LPtokenBalanceOfUser2BeforeFirstDeposit = await LPtoken.balanceOf(user2.address);
            await LPtoken.connect(user2).approve(vaultHealer.address, LPtokenBalanceOfUser2BeforeFirstDeposit); //no, I have to approve the vaulthealer surely?
            console.log("lp token approved by user 2")
            await vaultHealer.connect(user2)["deposit(uint256,uint256)"](pid,LPtokenBalanceOfUser2BeforeFirstDeposit);
            const vaultSharesTotalAfterUser2FirstWithdrawal = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            console.log(`deposited ${ethers.utils.formatEther(LPtokenBalanceOfUser2BeforeFirstDeposit)} lp tokens`)

            expect(LPtokenBalanceOfUser2BeforeFirstDeposit).to.equal(vaultSharesTotalAfterUser2FirstWithdrawal.sub(vaultSharesTotalAfterFirstWithdrawal)); //will this work for 2nd deposit? on normal masterchef?
        })

        // Deposit 100% of users LP tokens into vault, ensure balance increases as expected.
        it('Should accurately increase vaultSharesTotal upon second deposit by user1', async () => {
            await LPtoken.approve(vaultHealer.address, initialLPtokenBalance);
            const LPtokenBalanceBeforeSecondDeposit = await LPtoken.balanceOf(user1.address);
            const vaultSharesTotalBeforeSecondDeposit = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0

            await vaultHealer["deposit(uint256,uint256)"](pid, LPtokenBalanceBeforeSecondDeposit); //user1 (default signer) deposits LP tokens into specified pid vaulthealer
            
            const LPtokenBalanceAfterSecondDeposit = await LPtoken.balanceOf(user1.address);
            const vaultSharesTotalAfterSecondDeposit = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0;

            expect(LPtokenBalanceBeforeSecondDeposit.sub(LPtokenBalanceAfterSecondDeposit)).to.equal(vaultSharesTotalAfterSecondDeposit.sub(vaultSharesTotalBeforeSecondDeposit)); //will this work for 2nd deposit? on normal masterchef?
        })
        
        // Withdraw 100%
        it('Should withdraw remaining user1 balance back to user1, minus withdrawal fee (0.1%)', async () => {
            const LPtokenBalanceBeforeFinalWithdrawal = await LPtoken.balanceOf(user1.address);
            const UsersStakedTokensBeforeFinalWithdrawal = await vaultHealer.stakedWantTokens(pid, user1.address);

            await vaultHealer["withdraw(uint256,uint256)"](pid, UsersStakedTokensBeforeFinalWithdrawal); //user1 (default signer) deposits 1 of LP tokens into pid 0 of vaulthealer
            
            const LPtokenBalanceAfterFinalWithdrawal = await LPtoken.balanceOf(user1.address);
            UsersStakedTokensAfterFinalWithdrawal = await vaultHealer.stakedWantTokens(pid, user1.address);

            expect(LPtokenBalanceAfterFinalWithdrawal.sub(LPtokenBalanceBeforeFinalWithdrawal))
            .to.equal(
                (UsersStakedTokensBeforeFinalWithdrawal.sub(UsersStakedTokensAfterFinalWithdrawal))
                // .sub(
                //     (WITHDRAW_FEE_FACTOR_MAX.sub(withdrawFeeFactor))
                //     .mul(UsersStakedTokensBeforeFinalWithdrawal.sub(UsersStakedTokensAfterFinalWithdrawal))
                //     .div(WITHDRAW_FEE_FACTOR_MAX)
                // )
                );
        })

        //ensure no funds left in the vault.
        it('Should leave zero user1 funds in vault after 100% withdrawal', async () => {
            console.log(await crystlToken.balanceOf(strategyMasterHealer.address))
            expect(UsersStakedTokensAfterFinalWithdrawal.toNumber()).to.equal(0);
        })
        
    })
})
