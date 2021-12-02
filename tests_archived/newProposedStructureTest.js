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
const { crystlVault } = require('../configs/crystlVault'); //<-- replace all references to 'apeSwapVaults' (for example), with the right '...Vaults' name

const MASTERCHEF = apeSwapVaults[0].masterchef;
const TACTIC = apeSwapVaults[0].tactic;
const VAULT_HEALER = apeSwapVaults[0].vaulthealer;
const WANT = apeSwapVaults[0].want;
const EARNED = apeSwapVaults[0].earned;
const PATHS = apeSwapVaults[0].paths;
const PID = apeSwapVaults[0].PID;
const ROUTER = vaultSettings.standard[0];

const TOLERANCE = vaultSettings.standard[2];

// const [TOKEN0_TO_EARNED_PATH,, TOKEN1_TO_EARNED_PATH] = apeSwapVaults[0].paths;
const EARNED_TOKEN_1 = EARNED[0]
const EARNED_TOKEN_2 = EARNED[1]
const minBlocksBetweenSwaps = vaultSettings.standard[12];
var userRewardDebtAfterTime;

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
                [ ZERO_ADDRESS, FEE_ADDRESS, 10 ], // withdraw fee: token is not set here; standard fee address; 10 now means 0.1% consistent with other fees
                [ WMATIC, FEE_ADDRESS, 0 ], //earn fee: wmatic is paid; goes back to caller of earn; 0% rate
                [ WMATIC, FEE_ADDRESS, 500 ], //reward fee: paid in DAI; standard fee address; 0% rate
                [ CRYSTL, BURN_ADDRESS, 0 ] //burn fee: crystl to burn address; 5% rate
            ]
        
        vaultHealer = await VaultHealer.deploy(feeConfig);
        // console.log(vaultHealer.address);
        
        StrategyVHStandard = await ethers.getContractFactory(STRATEGY_CONTRACT_TYPE, {
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

        strategyVHStandard = await StrategyVHStandard.deploy(...DEPLOYMENT_VARS);
        // TOKEN0ADDRESS = await strategyVHStandard.lpToken[0];
        // TOKEN1ADDRESS = await strategyVHStandard.lpToken[1];
        // console.log(await strategyVHStandard.lpToken)
        LPtoken = await ethers.getContractAt(IUniswapV2Pair_abi, WANT);
        TOKEN0ADDRESS = await LPtoken.token0()
        TOKEN1ADDRESS = await LPtoken.token1()

        StrategyVHMaximizer = await ethers.getContractFactory(STRATEGY_CONTRACT_TYPE, {});
        strategyVHMaximizer = await StrategyVHMaximizer.deploy(...DEPLOYMENT_VARS);

        const CRYSTL_COMPOUNDER_VARS = [
            crystlVault[0]['want'], //wantAddress
            vaultHealer.address,
            crystlVault[0]['masterchef'], 
            crystlVault[0]['tactic'],
            crystlVault[0]['PID'], //what is the PID of this thing in our masterhealer?
            vaultSettings.standard,
            crystlVault[0]['earned'],
            ];

        strategyCrystlCompounder = await StrategyVHStandard.deploy(...CRYSTL_COMPOUNDER_VARS);


        vaultHealerOwner = await vaultHealer.owner();

        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [vaultHealerOwner],
          });
        vaultHealerOwnerSigner = await ethers.getSigner(vaultHealerOwner)
        
        await vaultHealer.connect(vaultHealerOwnerSigner).addPool(strategyVHStandard.address);
        strat1_pid = await vaultHealer.poolLength() -1;

        await vaultHealer.connect(vaultHealerOwnerSigner).addPool(strategyVHMaximizer.address);
        maximizer_strat_pid = await vaultHealer.poolLength() -1;

        await vaultHealer.connect(vaultHealerOwnerSigner).addPool(strategyCrystlCompounder.address);
        crystl_compounder_strat_pid = await vaultHealer.poolLength() -1;

        //create the staking pool for the boosted vault
        StakingPool = await ethers.getContractFactory("StakingPool", {});
        //need the wantToken address from the strategy!
        stakingPool = await StakingPool.deploy(
            vaultHealer.address, //and what about the strat1_pid? yes, the stakingPool needs it!, right up front...
            strat1_pid, //I'm hardcoding this for now - how can we do it in future??
            "0x76bf0c28e604cc3fe9967c83b3c3f31c213cfe64", //reward token = crystl
            1000000, //is this in WEI? assume so...
            21131210, //this is the block we're currently forking from - WATCH OUT if we change forking block
            21771725 //also watch out that we don't go past this, but we shouldn't
        )
        
        strategyVHStandard.setStakingPoolAddress(stakingPool.address);
        
        uniswapRouter = await ethers.getContractAt(IUniRouter02_abi, ROUTER);

        //fund the staking pool with reward token, Crystl 
        await uniswapRouter.swapExactETHForTokens(0, [WMATIC, CRYSTL], stakingPool.address, Date.now() + 900, { value: ethers.utils.parseEther("45") })

        await network.provider.send("hardhat_setBalance", [
            user1.address,
            "0x21E19E0C9BAB2400000", //amount of 1000 in hex
        ]);

        await network.provider.send("hardhat_setBalance", [
            user2.address,
            "0x21E19E0C9BAB2400000", //amount of 1000 in hex
        ]);

        if (TOKEN0ADDRESS == ethers.utils.getAddress(WMATIC) ){
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN0ADDRESS); 
            await wmatic_token.deposit({ value: ethers.utils.parseEther("4500") });
        } else {
            await uniswapRouter.swapExactETHForTokens(0, [WMATIC, TOKEN0ADDRESS], user1.address, Date.now() + 900, { value: ethers.utils.parseEther("4500") })
        }
        if (TOKEN1ADDRESS == ethers.utils.getAddress(WMATIC)) {
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN1ADDRESS); 
            await wmatic_token.deposit({ value: ethers.utils.parseEther("4500") });
        } else {
            await uniswapRouter.swapExactETHForTokens(0, [WMATIC, TOKEN1ADDRESS], user1.address, Date.now() + 900, { value: ethers.utils.parseEther("4500") })
        }

        if (TOKEN0ADDRESS == ethers.utils.getAddress(WMATIC) ){
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN0ADDRESS); 
            await wmatic_token.connect(user2).deposit({ value: ethers.utils.parseEther("4500") });
        } else {
            await uniswapRouter.connect(user2).swapExactETHForTokens(0, [WMATIC, TOKEN0ADDRESS], user2.address, Date.now() + 900, { value: ethers.utils.parseEther("4500") })
        }
        if (TOKEN1ADDRESS == ethers.utils.getAddress(WMATIC)) {
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN1ADDRESS); 
            await wmatic_token.connect(user2).deposit({ value: ethers.utils.parseEther("4500") });
        } else {
            await uniswapRouter.connect(user2).swapExactETHForTokens(0, [WMATIC, TOKEN1ADDRESS], user2.address, Date.now() + 900, { value: ethers.utils.parseEther("4500") })
        }

        //create instances of token0 and token1
        token0 = await ethers.getContractAt(token_abi, TOKEN0ADDRESS);
        token1 = await ethers.getContractAt(token_abi, TOKEN1ADDRESS);
        
        //user 1 adds liquidity to get LP tokens
        var token0BalanceUser1 = await token0.balanceOf(user1.address);
        await token0.approve(uniswapRouter.address, token0BalanceUser1);
        
        var token1BalanceUser1 = await token1.balanceOf(user1.address);
        await token1.approve(uniswapRouter.address, token1BalanceUser1);
        
        await uniswapRouter.addLiquidity(TOKEN0ADDRESS, TOKEN1ADDRESS, token0BalanceUser1, token1BalanceUser1, 0, 0, user1.address, Date.now() + 900)

        //user 2 adds liquidity to get LP tokens
        var token0BalanceUser2 = await token0.balanceOf(user2.address);
        await token0.connect(user2).approve(uniswapRouter.address, token0BalanceUser2);
        
        var token1BalanceUser2 = await token1.balanceOf(user2.address);
        await token1.connect(user2).approve(uniswapRouter.address, token1BalanceUser2);

        await uniswapRouter.connect(user2).addLiquidity(TOKEN0ADDRESS, TOKEN1ADDRESS, token0BalanceUser2, token1BalanceUser2, 0, 0, user2.address, Date.now() + 900)
        
    });

    describe(`Testing depositing into vault, compounding vault, withdrawing from vault:
    `, () => {
        // Stake a round number of LPs (e.g., 1 or 0.0001) - not a round number yet!
        it('Should deposit user1\'s whole balance of LP tokens into the vault, increasing vaultSharesTotal by the correct amount', async () => {
            initialLPtokenBalance = LPtoken.balanceOf(user1.address);
            await LPtoken.approve(vaultHealer.address, initialLPtokenBalance); //no, I have to approve the vaulthealer surely?
            LPtokenBalanceBeforeFirstDeposit = await LPtoken.balanceOf(user1.address);
            await vaultHealer["deposit(uint256,uint256)"](strat1_pid,initialLPtokenBalance);
            const vaultSharesTotalAfterFirstDeposit = await strategyVHStandard.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            // console.log(`deposited ${ethers.utils.formatEther(vaultSharesTotalAfterFirstDeposit)} lp tokens`)

            expect(LPtokenBalanceBeforeFirstDeposit).to.equal(vaultSharesTotalAfterFirstDeposit); //will this work for 2nd deposit? on normal masterchef?
        })
        
        it('Should mint ERC1155 tokens for this user, with the strat1_pid of the strategy and equal to LP tokens deposited', async () => {
            userBalanceOfStrategyTokens = await vaultHealer.balanceOf(user1.address, strat1_pid);
            expect(userBalanceOfStrategyTokens).to.eq(LPtokenBalanceBeforeFirstDeposit); 
        })

        it('Should allow user to boost by staking their receipt tokens in the stakingPool, showing a balanceOf in the pool afterwards', async () => {
            userBalanceOfStrategyTokensBeforeStaking = await vaultHealer.balanceOf(user1.address, strat1_pid);
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

        it('Should should allow the user to unstake their receipt tokens, and get correct amount back, and get reward out', async () => {
            user = await stakingPool.userInfo(user1.address);
            userBalanceOfStakingPoolBeforeWithdrawal = user.amount;
            // console.log(userBalanceOfStakingPoolBeforeWithdrawal)
            
            userBalanceInVaultBeforeWithdrawal = vaultHealer.stakedWantTokens(strat1_pid, user1.address)

            crystlToken = await ethers.getContractAt(token_abi, CRYSTL);
            userRewardTokenBalanceBeforeWithdrawal = await crystlToken.balanceOf(user1.address);

            await stakingPool.connect(user1)["withdraw(uint256)"](userBalanceOfStakingPool);

            user = await stakingPool.userInfo(user1.address);
            userBalanceOfStakingPoolAfterWithdrawal = user.amount;
            userBalanceInVaultAfterWithdrawal = await vaultHealer.stakedWantTokens(strat1_pid, user1.address)
            // console.log(userBalanceInVaultAfterWithdrawal)

            expect(userBalanceOfStakingPoolBeforeWithdrawal).to.eq(userBalanceInVaultAfterWithdrawal); //will only be true on first deposit?
            
            userRewardTokenBalanceAfterWithdrawal = await crystlToken.balanceOf(user1.address);
            expect(userRewardTokenBalanceAfterWithdrawal.sub(userRewardTokenBalanceBeforeWithdrawal)).to.eq(userRewardDebtAfterTime.add(1000000)); //adding one extra block of reward - this right?

        })

        //check that reward got returned to user1 on withdrawal

        // it('should return reward to user upon unstaking', async () => {
        //     // userRewardDebtBeforeWithdrawal = await stakingPool.pendingReward(user1.address);
        //     crystlToken = await ethers.getContractAt(token_abi, CRYSTL);
        //     userRewardTokenBalanceAfterWithdrawal = await crystlToken.balanceOf(user1.address);
        //     expect(userRewardTokenBalanceAfterWithdrawal).to.eq(userRewardDebtAfterTime);
        // })

        // Compound LPs (Call the earnSome function with this specific farm’s strat1_pid).
        // Check balance to ensure it increased as expected
        it('Should wait 10 blocks, then compound the LPs by calling earnSome(), so that vaultSharesTotal is greater after than before', async () => {
            const vaultSharesTotalBeforeCallingEarnSome = await strategyVHStandard.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            maticToken = await ethers.getContractAt(token_abi, WMATIC);

            balanceMaticAtFeeAddressBeforeEarn = await ethers.provider.getBalance(FEE_ADDRESS); //note: MATIC, not WMATIC

            // console.log(`Block number before calling earn ${await ethers.provider.getBlockNumber()}`)
            // console.log(`vaultSharesTotalBeforeCallingEarnSome: ${vaultSharesTotalBeforeCallingEarnSome}`)

            for (i=0; i<100;i++) { //minBlocksBetweenSwaps - can use this variable as an alternate to hardcoding a value
                await ethers.provider.send("evm_mine"); //creates a delay of 100 blocks - could adjust this to be minBlocksBetweenSwaps+1 blocks
            }

            await vaultHealer.earnSome([strat1_pid]);
            // console.log(`Block number after calling earn ${await ethers.provider.getBlockNumber()}`)

            vaultSharesTotalAfterCallingEarnSome = await strategyVHStandard.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            // console.log(`vaultSharesTotalAfterCallingEarnSome: ${vaultSharesTotalAfterCallingEarnSome}`)

            const differenceInVaultSharesTotal = vaultSharesTotalAfterCallingEarnSome.sub(vaultSharesTotalBeforeCallingEarnSome);

            expect(differenceInVaultSharesTotal).to.be.gt(0); //.toNumber()
        }) 

        it('Should pay 5% of earnedAmt to the feeAddress with each earn, in WMATIC', async () => {
            balanceMaticAtFeeAddressAfterEarn = await ethers.provider.getBalance(FEE_ADDRESS); //note: MATIC, not WMATIC
            expect(balanceMaticAtFeeAddressAfterEarn).to.be.gt(balanceMaticAtFeeAddressBeforeEarn);
            //this doesn't work because user had to pay gas
        })
        
        // Unstake 50% of LPs. 
        // Check transaction to ensure withdraw fee amount is as expected and amount withdrawn in as expected
        it('Should withdraw 50% of LPs with correct withdraw fee amount (0.1%) and decrease users stakedWantTokens balance correctly', async () => {
            const LPtokenBalanceBeforeFirstWithdrawal = await LPtoken.balanceOf(user1.address);
            const UsersStakedTokensBeforeFirstWithdrawal = await vaultHealer.stakedWantTokens(strat1_pid, user1.address);

            await vaultHealer["withdraw(uint256,uint256)"](strat1_pid, UsersStakedTokensBeforeFirstWithdrawal.div(2)); 
            
            const LPtokenBalanceAfterFirstWithdrawal = await LPtoken.balanceOf(user1.address);
            vaultSharesTotalAfterFirstWithdrawal = await strategyVHStandard.connect(vaultHealerOwnerSigner).vaultSharesTotal() 

            expect(LPtokenBalanceAfterFirstWithdrawal.sub(LPtokenBalanceBeforeFirstWithdrawal))
            .to.equal(
                (vaultSharesTotalAfterCallingEarnSome.sub(vaultSharesTotalAfterFirstWithdrawal))
                .sub((WITHDRAW_FEE_FACTOR_MAX.sub(withdrawFeeFactor))
                .mul(vaultSharesTotalAfterCallingEarnSome.sub(vaultSharesTotalAfterFirstWithdrawal))
                .div(WITHDRAW_FEE_FACTOR_MAX))
                )
                ;
        })
        // Stake a round number of LPs (e.g., 1 or 0.0001) - not a round number yet!
        it('Should deposit user2\'s whole balance of LP tokens into the vault, increasing vaultSharesTotal by the correct amount', async () => {
            const LPtokenBalanceOfUser2BeforeFirstDeposit = await LPtoken.balanceOf(user2.address);
            await LPtoken.connect(user2).approve(vaultHealer.address, LPtokenBalanceOfUser2BeforeFirstDeposit); //no, I have to approve the vaulthealer surely?
            // console.log("lp token approved by user 2")
            await vaultHealer.connect(user2)["deposit(uint256,uint256)"](strat1_pid,LPtokenBalanceOfUser2BeforeFirstDeposit);
            const vaultSharesTotalAfterUser2FirstWithdrawal = await strategyVHStandard.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            // console.log(`deposited ${ethers.utils.formatEther(LPtokenBalanceOfUser2BeforeFirstDeposit)} lp tokens`)

            expect(LPtokenBalanceOfUser2BeforeFirstDeposit).to.equal(vaultSharesTotalAfterUser2FirstWithdrawal.sub(vaultSharesTotalAfterFirstWithdrawal)); //will this work for 2nd deposit? on normal masterchef?
        })

        // Deposit 100% of users LP tokens into vault, ensure balance increases as expected.
        it('Should accurately increase vaultSharesTotal upon second deposit by user1', async () => {
            await LPtoken.approve(vaultHealer.address, initialLPtokenBalance);
            const LPtokenBalanceBeforeSecondDeposit = await LPtoken.balanceOf(user1.address);
            const vaultSharesTotalBeforeSecondDeposit = await strategyVHStandard.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0

            await vaultHealer["deposit(uint256,uint256)"](strat1_pid, LPtokenBalanceBeforeSecondDeposit); //user1 (default signer) deposits LP tokens into specified strat1_pid vaulthealer
            
            const LPtokenBalanceAfterSecondDeposit = await LPtoken.balanceOf(user1.address);
            const vaultSharesTotalAfterSecondDeposit = await strategyVHStandard.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0;

            expect(LPtokenBalanceBeforeSecondDeposit.sub(LPtokenBalanceAfterSecondDeposit)).to.equal(vaultSharesTotalAfterSecondDeposit.sub(vaultSharesTotalBeforeSecondDeposit)); //will this work for 2nd deposit? on normal masterchef?
        })
        

        // Withdraw 100%
        it('Should withdraw remaining user1 balance back to user1, with all of it staked in boosting pool, minus withdrawal fee (0.1%)', async () => {
            userBalanceOfStrategyTokensBeforeStaking = await vaultHealer.balanceOf(user1.address, strat1_pid);

            await vaultHealer.connect(user1).setApprovalForAll(stakingPool.address, true); //dangerous to approve all forever?

            await stakingPool.connect(user1).deposit(userBalanceOfStrategyTokensBeforeStaking);
            user = await stakingPool.userInfo(user1.address);
            userBalanceOfStakingPool = user.amount;

            userWantTokensBeforeWithdrawal = await vaultHealer.stakedWantTokens(strat1_pid, user1.address);
            const LPtokenBalanceBeforeFinalWithdrawal = await LPtoken.balanceOf(user1.address)
            // console.log(userWantTokensBeforeWithdrawal);

            // console.log("LPtokenBalanceBeforeFinalWithdrawal - user1")
            // console.log(ethers.utils.formatEther(LPtokenBalanceBeforeFinalWithdrawal))

            const UsersStakedTokensBeforeFinalWithdrawal = await vaultHealer.stakedWantTokens(strat1_pid, user1.address);
            // console.log("UsersStakedTokensBeforeFinalWithdrawal - user1")
            // console.log(ethers.utils.formatEther(UsersStakedTokensBeforeFinalWithdrawal))
            userBoostedWantTokensBeforeWithdrawal = await vaultHealer.boostedWantTokens(strat1_pid, user1.address);
            // console.log("userBoostedWantTokensBeforeWithdrawal");
            // console.log(ethers.utils.formatEther(userBoostedWantTokensBeforeWithdrawal));

            await vaultHealer["withdraw(uint256,uint256)"](strat1_pid, UsersStakedTokensBeforeFinalWithdrawal+userBoostedWantTokensBeforeWithdrawal); //user1 (default signer) deposits 1 of LP tokens into strat1_pid 0 of vaulthealer
            
            const LPtokenBalanceAfterFinalWithdrawal = await LPtoken.balanceOf(user1.address);
            // console.log("LPtokenBalanceAfterFinalWithdrawal - user1")
            // console.log(ethers.utils.formatEther(LPtokenBalanceAfterFinalWithdrawal))

            UsersStakedTokensAfterFinalWithdrawal = await vaultHealer.stakedWantTokens(strat1_pid, user1.address);
            // console.log("UsersStakedTokensAfterFinalWithdrawal - user1")
            // console.log(ethers.utils.formatEther(UsersStakedTokensAfterFinalWithdrawal))
            
            userBoostedWantTokensAfterWithdrawal = await vaultHealer.boostedWantTokens(strat1_pid, user1.address);

            expect(LPtokenBalanceAfterFinalWithdrawal.sub(LPtokenBalanceBeforeFinalWithdrawal))
            .to.equal(
                (UsersStakedTokensBeforeFinalWithdrawal.add(userBoostedWantTokensBeforeWithdrawal).sub(UsersStakedTokensAfterFinalWithdrawal).sub(userBoostedWantTokensAfterWithdrawal))
                .sub(
                    (WITHDRAW_FEE_FACTOR_MAX.sub(withdrawFeeFactor))
                    .mul(UsersStakedTokensBeforeFinalWithdrawal.add(userBoostedWantTokensBeforeWithdrawal).sub(UsersStakedTokensAfterFinalWithdrawal).sub(userBoostedWantTokensAfterWithdrawal))
                    .div(WITHDRAW_FEE_FACTOR_MAX)
                )
                );
        })

        //ensure no funds left in the vault.
        it('Should leave zero user1 funds in vault after 100% withdrawal', async () => {
            // console.log(await crystlToken.balanceOf(strategyVHStandard.address))
            expect(UsersStakedTokensAfterFinalWithdrawal.toNumber()).to.equal(0);
        })

        it('Should leave zero user1 funds in stakingPool after 100% withdrawal', async () => {
            // console.log(await crystlToken.balanceOf(strategyVHStandard.address))
            expect(userBoostedWantTokensAfterWithdrawal.toNumber()).to.equal(0);
        })
        
    })
})

