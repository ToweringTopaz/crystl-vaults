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

const MASTERCHEF = apeSwapVaults[1].masterchef;
const TACTIC = apeSwapVaults[1].tactic;
const VAULT_HEALER = apeSwapVaults[1].vaulthealer;
const WANT = apeSwapVaults[1].want;
const EARNED = apeSwapVaults[1].earned;
const PATHS = apeSwapVaults[1].paths;
const PID = apeSwapVaults[1].PID;
const ROUTER = vaultSettings.standard[0];

const TOLERANCE = vaultSettings.standard[2];

// const [TOKEN0_TO_EARNED_PATH,, TOKEN1_TO_EARNED_PATH] = apeSwapVaults[1].paths;
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
        
        StrategyVHStandard = await ethers.getContractFactory('StrategyVHStandard', {
            // libraries: {
            //     LibVaultSwaps: "0x1B20Dab7BE777a9CFC363118BC46f7905A7628a1",
            //     LibVaultConfig: "0x95Fe76f0BA650e7C3a3E1Bb6e6DFa0e8bA28fd6d"
            //   },
        });        
        const DEPLOYMENT_VARS = [
            apeSwapVaults[1]['want'],
            vaultHealer.address,
            apeSwapVaults[1]['masterchef'],
            apeSwapVaults[1]['tactic'],
            apeSwapVaults[1]['PID'],
            vaultSettings.standard,
            apeSwapVaults[1]['earned'],
            ];

        strategyVHStandard = await StrategyVHStandard.deploy(...DEPLOYMENT_VARS);
        // TOKEN0ADDRESS = await strategyVHStandard.lpToken[0];
        // TOKEN1ADDRESS = await strategyVHStandard.lpToken[1];
        // console.log(await strategyVHStandard.lpToken)
        LPtoken = await ethers.getContractAt(IUniswapV2Pair_abi, WANT);
        TOKEN0ADDRESS = await LPtoken.token0()
        TOKEN1ADDRESS = await LPtoken.token1()

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

        StrategyVHMaximizer = await ethers.getContractFactory('StrategyVHMaximizer', {});

        const MAXIMIZER_VARS = [
            apeSwapVaults[1]['want'],
            vaultHealer.address,
            apeSwapVaults[1]['masterchef'],
            apeSwapVaults[1]['tactic'],
            apeSwapVaults[1]['PID'],
            vaultSettings.standard,
            apeSwapVaults[1]['earned'],
            strategyCrystlCompounder.address
            ];

        strategyVHMaximizer = await StrategyVHMaximizer.deploy(...MAXIMIZER_VARS);

        vaultHealerOwner = await vaultHealer.owner();

        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [vaultHealerOwner],
          });
        vaultHealerOwnerSigner = await ethers.getSigner(vaultHealerOwner)
        
        await vaultHealer.connect(vaultHealerOwnerSigner).addPool(strategyVHStandard.address);
        strat1_pid = await vaultHealer.poolLength() -1;
        console.log("strat1_pid");
        console.log(strat1_pid);

        await vaultHealer.connect(vaultHealerOwnerSigner).addPool(strategyVHMaximizer.address);
        maximizer_strat_pid = await vaultHealer.poolLength() -1;
        console.log("maximizer_strat_pid");
        console.log(maximizer_strat_pid);

        await vaultHealer.connect(vaultHealerOwnerSigner).addPool(strategyCrystlCompounder.address);
        crystl_compounder_strat_pid = await vaultHealer.poolLength() -1;
        console.log("crystl_compounder_strat_pid");
        console.log(crystl_compounder_strat_pid);

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

    describe(`Testing depositing into maximizer vault, compounding maximizer vault, withdrawing from maximizer vault:
    `, () => {
        // Stake a round number of LPs (e.g., 1 or 0.0001) - not a round number yet!
        it('Should deposit user1\'s 100 LP tokens into the vault, increasing vaultSharesTotal by the correct amount', async () => {
            // initialLPtokenBalance = await LPtoken.balanceOf(user1.address);
            await LPtoken.approve(vaultHealer.address, ethers.utils.parseEther("5000")); //no, I have to approve the vaulthealer surely?
            LPtokenBalanceBeforeFirstDeposit = await LPtoken.balanceOf(user1.address);
            await vaultHealer["deposit(uint256,uint256)"](maximizer_strat_pid, ethers.utils.parseEther("5000"));
            const vaultSharesTotalAfterFirstDeposit = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            console.log(`User1 deposited 100 LP tokens`)
            console.log(`Vault Shares Total went up by ${ethers.utils.formatEther(vaultSharesTotalAfterFirstDeposit)} LP tokens`)

            expect(ethers.utils.parseEther("5000")).to.equal(vaultSharesTotalAfterFirstDeposit);
        })
        
        it('Should mint ERC1155 tokens for this user, with the maximizer_strat_pid of the strategy and equal to LP tokens deposited', async () => {
            userBalanceOfStrategyTokens = await vaultHealer.balanceOf(user1.address, maximizer_strat_pid);
            console.log(`User1 balance of ERC115 tokens is now ${ethers.utils.formatEther(userBalanceOfStrategyTokens)} tokens`)
            expect(userBalanceOfStrategyTokens).to.eq(ethers.utils.parseEther("5000")); 
        })

        // Compound LPs (Call the earnSome function with this specific farm’s maximizer_strat_pid).
        // Check balance to ensure it increased as expected
        it('Should wait 10 blocks, then compound the maximizer vault by calling earnSome(), resulting in an increase in crystl in the crystl compounder', async () => {
            const vaultSharesTotalBeforeCallingEarnSome = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            console.log(`We start with ${ethers.utils.formatEther(vaultSharesTotalBeforeCallingEarnSome)} tokens in the crystl compounder strategy`)
            console.log(`We let 100 blocks pass...`)

            maticToken = await ethers.getContractAt(token_abi, WMATIC);

            balanceMaticAtFeeAddressBeforeEarn = await ethers.provider.getBalance(FEE_ADDRESS); //note: MATIC, not WMATIC

            // console.log(`Block number before calling earn ${await ethers.provider.getBlockNumber()}`)
            // console.log(`vaultSharesTotalBeforeCallingEarnSome: ${vaultSharesTotalBeforeCallingEarnSome}`)

            for (i=0; i<100;i++) { //minBlocksBetweenSwaps - can use this variable as an alternate to hardcoding a value
                await ethers.provider.send("evm_mine"); //creates a delay of 100 blocks - could adjust this to be minBlocksBetweenSwaps+1 blocks
            }

            await vaultHealer.earnSome([maximizer_strat_pid]);
            // console.log(`Block number after calling earn ${await ethers.provider.getBlockNumber()}`)

            vaultSharesTotalAfterCallingEarnSome = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            console.log(`After the earn call we have ${ethers.utils.formatEther(vaultSharesTotalAfterCallingEarnSome)} tokens in the crystl compounder strategy`)

            const differenceInVaultSharesTotal = vaultSharesTotalAfterCallingEarnSome.sub(vaultSharesTotalBeforeCallingEarnSome);

            expect(differenceInVaultSharesTotal).to.be.gt(0); //.toNumber()
        }) 

        it('Should pay 5% of earnedAmt to the feeAddress with each earn, in WMATIC', async () => {
            balanceMaticAtFeeAddressAfterEarn = await ethers.provider.getBalance(FEE_ADDRESS); //note: MATIC, not WMATIC
            console.log(`MATIC at Fee Address went up by ${ethers.utils.formatEther(balanceMaticAtFeeAddressAfterEarn.sub(balanceMaticAtFeeAddressBeforeEarn))} tokens`)
            expect(balanceMaticAtFeeAddressAfterEarn).to.be.gt(balanceMaticAtFeeAddressBeforeEarn);
        })

        // Compound LPs (Call the earnSome function with this specific farm’s maximizer_strat_pid).
        // Check balance to ensure it increased as expected
        it('Should wait 10 blocks, then compound the crystl Compounder by calling earnSome(), so that vaultSharesTotal is greater after than before', async () => {
            const vaultSharesTotalBeforeCallingEarnSome = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            console.log(`Before calling earn on the crystl compounder, we have ${ethers.utils.formatEther(vaultSharesTotalBeforeCallingEarnSome)} tokens in it`)
            console.log(`We let 100 blocks pass...`)
            // console.log(`Block number before calling earn ${await ethers.provider.getBlockNumber()}`)
            // console.log(`vaultSharesTotalBeforeCallingEarnSome: ${vaultSharesTotalBeforeCallingEarnSome}`)

            for (i=0; i<100;i++) { //minBlocksBetweenSwaps - can use this variable as an alternate to hardcoding a value
                await ethers.provider.send("evm_mine"); //creates a delay of 100 blocks - could adjust this to be minBlocksBetweenSwaps+1 blocks
            }

            await vaultHealer.earnSome([crystl_compounder_strat_pid]);
            // console.log(`Block number after calling earn ${await ethers.provider.getBlockNumber()}`)

            vaultSharesTotalInCrystalCompounderAfterCallingEarnSome = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            // console.log(`vaultSharesTotalInCrystalCompounderAfterCallingEarnSome: ${vaultSharesTotalInCrystalCompounderAfterCallingEarnSome}`)
            console.log(`After calling earn on the crystl compounder, we have ${ethers.utils.formatEther(vaultSharesTotalInCrystalCompounderAfterCallingEarnSome)} tokens in it`)

            const differenceInVaultSharesTotal = vaultSharesTotalInCrystalCompounderAfterCallingEarnSome.sub(vaultSharesTotalBeforeCallingEarnSome);

            expect(differenceInVaultSharesTotal).to.be.gt(0); //.toNumber()
        }) 
        
        // Unstake 50% of LPs. 
        // Check transaction to ensure withdraw fee amount is as expected and amount withdrawn in as expected
        it('Should withdraw 50% of LPs with correct withdraw fee amount (0.1%) and decrease users stakedWantTokens balance correctly', async () => {
            const LPtokenBalanceBeforeFirstWithdrawal = await LPtoken.balanceOf(user1.address);
            const UsersStakedTokensBeforeFirstWithdrawal = await vaultHealer.stakedWantTokens(maximizer_strat_pid, user1.address);
            // console.log(ethers.utils.formatEther(UsersStakedTokensBeforeFirstWithdrawal));

            vaultSharesTotalInMaximizerBeforeWithdraw = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            crystlToken = await ethers.getContractAt(token_abi, CRYSTL);
            user1CrystlBalanceBeforeWithdraw = await crystlToken.balanceOf(user1.address);
            // console.log("user1CrystlBalanceBeforeWithdraw");
            // console.log(user1CrystlBalanceBeforeWithdraw);
            console.log(`We withdraw ${ethers.utils.formatEther(UsersStakedTokensBeforeFirstWithdrawal.div(2))} tokens from the maximizer vault`)

            await vaultHealer["withdraw(uint256,uint256)"](maximizer_strat_pid, UsersStakedTokensBeforeFirstWithdrawal.div(2)); 
            
            const LPtokenBalanceAfterFirstWithdrawal = await LPtoken.balanceOf(user1.address);
            // console.log(ethers.utils.formatEther(LPtokenBalanceAfterFirstWithdrawal));

            vaultSharesTotalAfterFirstWithdrawal = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() 
            // console.log(ethers.utils.formatEther(vaultSharesTotalInMaximizerBeforeWithdraw));
            // console.log(ethers.utils.formatEther(vaultSharesTotalAfterFirstWithdrawal));

            expect(LPtokenBalanceAfterFirstWithdrawal.sub(LPtokenBalanceBeforeFirstWithdrawal))
            .to.equal(
                (vaultSharesTotalInMaximizerBeforeWithdraw.sub(vaultSharesTotalAfterFirstWithdrawal))
                .sub((WITHDRAW_FEE_FACTOR_MAX.sub(withdrawFeeFactor))
                .mul(vaultSharesTotalInMaximizerBeforeWithdraw.sub(vaultSharesTotalAfterFirstWithdrawal))
                .div(WITHDRAW_FEE_FACTOR_MAX))
                )
                ;
        })

        // withdraw should also cause crystl to be returned to the user (all of it)
        it('Should return crystl harvest to user when they withdraw (above test)', async () => {
            user1CrystlBalanceAfterWithdraw = await crystlToken.balanceOf(user1.address);
            // console.log("user1CrystlBalanceAfterWithdraw");
            // console.log(user1CrystlBalanceAfterWithdraw);
            console.log(`The user got ${ethers.utils.formatEther((user1CrystlBalanceAfterWithdraw).sub(user1CrystlBalanceBeforeWithdraw))} tokens back from the maximizer vault`)

            expect(user1CrystlBalanceAfterWithdraw).to.be.gt(user1CrystlBalanceBeforeWithdraw);
        })

        // Stake a round number of LPs (e.g., 1 or 0.0001) - not a round number yet!
        it('Should deposit user2\'s whole balance of LP tokens into the vault, increasing vaultSharesTotal by the correct amount', async () => {
            // const LPtokenBalanceOfUser2BeforeFirstDeposit = await LPtoken.balanceOf(user2.address);
            await LPtoken.connect(user2).approve(vaultHealer.address, ethers.utils.parseEther("150")); //no, I have to approve the vaulthealer surely?
            // console.log("lp token approved by user 2")
            await vaultHealer.connect(user2)["deposit(uint256,uint256)"](maximizer_strat_pid, ethers.utils.parseEther("150"));
            const vaultSharesTotalAfterUser2FirstWithdrawal = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            console.log(`User 2 deposited 150 LP tokens`)

            expect(ethers.utils.parseEther("150")).to.equal(vaultSharesTotalAfterUser2FirstWithdrawal.sub(vaultSharesTotalAfterFirstWithdrawal)); //will this work for 2nd deposit? on normal masterchef?
        })

        // Deposit 100% of users LP tokens into vault, ensure balance increases as expected.
        it('Should accurately increase vaultSharesTotal upon second deposit by user1', async () => {
            await LPtoken.approve(vaultHealer.address, ethers.utils.parseEther("200"));
            // console.log("initialLPtokenBalance");
            // console.log(ethers.utils.formatEther(initialLPtokenBalance));

            const LPtokenBalanceBeforeSecondDeposit = await LPtoken.balanceOf(user1.address);
            // console.log("LPtokenBalanceBeforeSecondDeposit");
            // console.log(ethers.utils.formatEther(LPtokenBalanceBeforeSecondDeposit));

            const vaultSharesTotalBeforeSecondDeposit = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            // console.log("vaultSharesTotalBeforeSecondDeposit");
            // console.log(ethers.utils.formatEther(vaultSharesTotalBeforeSecondDeposit));

            await vaultHealer["deposit(uint256,uint256)"](maximizer_strat_pid, ethers.utils.parseEther("200")); //user1 (default signer) deposits LP tokens into specified maximizer_strat_pid vaulthealer
            console.log(`User 1 deposited 200 LP tokens`)

            const LPtokenBalanceAfterSecondDeposit = await LPtoken.balanceOf(user1.address);
            // console.log("LPtokenBalanceAfterSecondDeposit");
            // console.log(ethers.utils.formatEther(LPtokenBalanceAfterSecondDeposit));

            const vaultSharesTotalAfterSecondDeposit = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0;
            // console.log("vaultSharesTotalAfterSecondDeposit");
            // console.log(ethers.utils.formatEther(vaultSharesTotalAfterSecondDeposit));

            expect(ethers.utils.parseEther("200")).to.equal(vaultSharesTotalAfterSecondDeposit.sub(vaultSharesTotalBeforeSecondDeposit)); //will this work for 2nd deposit? on normal masterchef?
        })
        

        // Withdraw 100%
        it('Should withdraw remaining user1 balance back to user1, with all of it staked in boosting pool, minus withdrawal fee (0.1%)', async () => {
            userBalanceOfStrategyTokensBeforeStaking = await vaultHealer.balanceOf(user1.address, maximizer_strat_pid);
            console.log(`User1 now has ${ethers.utils.formatEther(userBalanceOfStrategyTokensBeforeStaking)} tokens in the maximizer vault`)

            const LPtokenBalanceBeforeFinalWithdrawal = await LPtoken.balanceOf(user1.address)
            // console.log("LPtokenBalanceBeforeFinalWithdrawal - user1")
            // console.log(ethers.utils.formatEther(LPtokenBalanceBeforeFinalWithdrawal))

            const UsersStakedTokensBeforeFinalWithdrawal = await vaultHealer.stakedWantTokens(maximizer_strat_pid, user1.address);
            // console.log("UsersStakedTokensBeforeFinalWithdrawal - user1")
            // console.log(ethers.utils.formatEther(UsersStakedTokensBeforeFinalWithdrawal))

            await vaultHealer["withdraw(uint256,uint256)"](maximizer_strat_pid, UsersStakedTokensBeforeFinalWithdrawal); //user1 (default signer) deposits 1 of LP tokens into maximizer_strat_pid 0 of vaulthealer
            
            const LPtokenBalanceAfterFinalWithdrawal = await LPtoken.balanceOf(user1.address);
            // console.log("LPtokenBalanceAfterFinalWithdrawal - user1")
            // console.log(ethers.utils.formatEther(LPtokenBalanceAfterFinalWithdrawal))

            UsersStakedTokensAfterFinalWithdrawal = await vaultHealer.stakedWantTokens(maximizer_strat_pid, user1.address);
            // console.log("UsersStakedTokensAfterFinalWithdrawal - user1")
            // console.log(ethers.utils.formatEther(UsersStakedTokensAfterFinalWithdrawal))

            expect(LPtokenBalanceAfterFinalWithdrawal.sub(LPtokenBalanceBeforeFinalWithdrawal))
            .to.equal(
                (UsersStakedTokensBeforeFinalWithdrawal.sub(UsersStakedTokensAfterFinalWithdrawal))
                .sub(
                    (WITHDRAW_FEE_FACTOR_MAX.sub(withdrawFeeFactor))
                    .mul(UsersStakedTokensBeforeFinalWithdrawal.sub(UsersStakedTokensAfterFinalWithdrawal))
                    .div(WITHDRAW_FEE_FACTOR_MAX)
                )
                );
        })

        //ensure no funds left in the vault.
        it('Should leave zero user1 funds in vault after 100% withdrawal', async () => {
            console.log(`User1 now has ${ethers.utils.formatEther(UsersStakedTokensAfterFinalWithdrawal)} tokens in the maximizer vault`)
            expect(UsersStakedTokensAfterFinalWithdrawal.toNumber()).to.equal(0);
        })    
        
        // withdraw should also cause crystl to be returned to the user (all of it)
        it('Should return crystl harvest to user when they withdraw (above test)', async () => {
            user1CrystlBalanceAfterWithdraw = await crystlToken.balanceOf(user1.address);
            console.log(`User1 now has ${ethers.utils.formatEther(user1CrystlBalanceAfterWithdraw)} crystl tokens`)
            expect(user1CrystlBalanceAfterWithdraw).to.be.gt(user1CrystlBalanceBeforeWithdraw);
        })
    })
})

