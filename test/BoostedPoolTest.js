// import hre from "hardhat";

const { tokens, accounts } = require('../configs/addresses.js');
const { WMATIC, CRYSTL, DAI } = tokens.polygon;
const { FEE_ADDRESS, BURN_ADDRESS, ZERO_ADDRESS } = accounts.polygon;
const { expect } = require('chai');
const { ethers } = require('hardhat');
const { IUniRouter02_abi } = require('./abi_files/IUniRouter02_abi.js');
const { token_abi } = require('./abi_files/token_abi.js');
const { vaultHealer_abi } = require('./abi_files/vaultHealer_abi.js'); //TODO - this would have to change if we change the vaulthealer
const { IWETH_abi } = require('./abi_files/IWETH_abi.js');
// const { IMasterchef_abi } = require('./IMasterchef_abi.js');
const { IUniswapV2Pair_abi } = require('./abi_files/IUniswapV2Pair_abi.js');

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
        /*
        // vaultHealer = await ethers.getContractAt(vaultHealer_abi, VAULT_HEALER);
		
		Magnetite = await ethers.getContractFactory("Magnetite");
		ZapDeployer = await ethers.getContractFactory("QuartzUniV2ZapDeployer");
		VaultView = await ethers.getContractFactory("VaultView");
		
		magnetite = await Magnetite.deploy();
		zapDeployer = await ZapDeployer.deploy();
		vaultView = await VaultView.deploy();
		*/
        VaultHealer = await ethers.getContractFactory("VaultHealer", {
            // libraries: {
            //     LibMagnetite: "0xf34b0c8ab719dED106D6253798D3ed5c7fCA2E04",
            //     LibVaultConfig: "0x95Fe76f0BA650e7C3a3E1Bb6e6DFa0e8bA28fd6d"
            //   },
        });
        const feeConfig = 
            [
                [ FEE_ADDRESS, 0 ], //earn fee: wmatic is paid; goes back to caller of earn; 0% rate
                [ FEE_ADDRESS, 500 ], //reward fee: paid in DAI; standard fee address; 0% rate
                [ BURN_ADDRESS, 0 ] //burn fee: crystl to burn address; 5% rate
            ]
        
            vaultHealer = await VaultHealer.deploy(FEE_ADDRESS, 10, [ FEE_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS ], [500, 0, 0]);
            vaultHealerView = await ethers.getContractAt('VaultView', vaultHealer.address);
            quartzUniV2Zap = await ethers.getContractAt('QuartzUniV2Zap', await vaultHealerView.zap());
            
            StrategyVHStandard = await ethers.getContractFactory('StrategyVHStandard', {
                // libraries: {
            //     LibVaultSwaps: "0x1B20Dab7BE777a9CFC363118BC46f7905A7628a1",
            //     LibVaultConfig: "0x95Fe76f0BA650e7C3a3E1Bb6e6DFa0e8bA28fd6d"
            //   },
        });        
        strategyImplementation = await StrategyVHStandard.deploy();
		const abiCoder = new ethers.utils.AbiCoder;
        const NULL_BYTES = [];
        const DEPLOYMENT_DATA = abiCoder.encode(
			[ "address", "address", "address", "uint256", "tuple(address, uint16, uint32, bool, address, uint96)", "address[]", "uint256" ],
			[
				apeSwapVaults[1]['want'],
				apeSwapVaults[1]['masterchef'],
				apeSwapVaults[1]['tactic'],
				apeSwapVaults[1]['PID'],
				vaultSettings.standard,
				apeSwapVaults[1]['earned'],
				0
            ]
		);
        LPtoken = await ethers.getContractAt(IUniswapV2Pair_abi, WANT);
        TOKEN0ADDRESS = await LPtoken.token0()
        TOKEN1ADDRESS = await LPtoken.token1()

        vaultHealerOwner = await vaultHealerView.owner();

        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [vaultHealerOwner],
          });
        vaultHealerOwnerSigner = await ethers.getSigner(vaultHealerOwner)
        
        await vaultHealer.connect(vaultHealerOwnerSigner).createVault(strategyImplementation.address, DEPLOYMENT_DATA);
        strat1_pid = await vaultHealerView.vaultLength() -1;
		strategyVHStandard = await vaultHealerView.strat(strat1_pid);

        strategyVHStandard = await ethers.getContractAt('StrategyVHStandard', strategyVHStandard);
        console.log("4");
        //create the staking pool for the boosted vault
        BoostPool = await ethers.getContractFactory("BoostPool", {});
        //need the wantToken address from the strategy!
        boostPool = await BoostPool.deploy(
            vaultHealer.address, //and what about the strat1_pid? yes, the boostPool needs it!, right up front...
            strat1_pid, //I'm hardcoding this for now - how can we do it in future??
            "0x76bf0c28e604cc3fe9967c83b3c3f31c213cfe64", //reward token = crystl
            1000000, //is this in WEI? assume so...
            22051958, //this is the block we're currently forking from - WATCH OUT if we change forking block
            22051958+640515 //also watch out that we don't go past this, but we shouldn't
        )
        
        vaultHealer.addBoost(boostPool.address);
        
        uniswapRouter = await ethers.getContractAt(IUniRouter02_abi, ROUTER);

        //fund the staking pool with reward token, Crystl 
        await uniswapRouter.swapExactETHForTokens(0, [WMATIC, CRYSTL], boostPool.address, Date.now() + 900, { value: ethers.utils.parseEther("45") })
        console.log("5");

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
        it('Should deposit user1\'s 100 LP tokens into the vault, increasing vaultSharesTotal by the correct amount', async () => {
            // initialLPtokenBalance = await LPtoken.balanceOf(user1.address);
            user1InitialDeposit = ethers.utils.parseEther("5000");

            await LPtoken.connect(user1).approve(vaultHealer.address, user1InitialDeposit);
            LPtokenBalanceBeforeFirstDeposit = await LPtoken.balanceOf(user1.address);
            await vaultHealer.connect(user1)["deposit(uint256,uint256)"](strat1_pid, user1InitialDeposit);
            const vaultSharesTotalAfterFirstDeposit = await strategyVHStandard.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            console.log(`User1 deposits ${ethers.utils.formatEther(user1InitialDeposit)} LP tokens`)
            console.log(`Vault Shares Total went up by ${ethers.utils.formatEther(vaultSharesTotalAfterFirstDeposit)} LP tokens`)

            expect(user1InitialDeposit).to.equal(vaultSharesTotalAfterFirstDeposit);
        })
        
        it('Should mint ERC1155 tokens for this user, with the strat1_pid of the strategy and equal to LP tokens deposited', async () => {
            userBalanceOfStrategyTokens = await vaultHealer.balanceOf(user1.address, strat1_pid);
            console.log(`User1 balance of ERC1155 tokens is now ${ethers.utils.formatEther(userBalanceOfStrategyTokens)} tokens`)
            // console.log(await vaultHealer.userTotals(strat1_pid, user1.address));
            expect(userBalanceOfStrategyTokens).to.eq(user1InitialDeposit); 
        })

        it('Should allow user to boost via enableBoost, showing a balanceOf in the pool afterwards', async () => {
            userBalanceOfStrategyTokensBeforeStaking = await vaultHealer.balanceOf(user1.address, strat1_pid);
            await vaultHealer.connect(user1)["enableBoost(uint256,uint256)"](strat1_pid, 0);

            user = await boostPool.userInfo(user1.address);
            userBalanceOfBoostPool = user.amount;
            expect(userBalanceOfBoostPool).to.equal(userBalanceOfStrategyTokensBeforeStaking);
        })

        it('Should accumulate rewards for the staked user over time', async () => {
            userRewardDebtAtStart = await boostPool.pendingReward(user1.address);
            console.log(userRewardDebtAtStart);
            for (i=0; i<1000;i++) { //minBlocksBetweenSwaps
                await ethers.provider.send("evm_mine"); //creates a delay of minBlocksBetweenSwaps+1 blocks
                }
            
            userRewardDebtAfterTime = await boostPool.pendingReward(user1.address);;
            console.log(userRewardDebtAfterTime);
            expect(userRewardDebtAfterTime).to.be.gt(userRewardDebtAtStart); //will only be true on first deposit?
        })

        it('Should allow the user to harvest their boost pool rewards', async () => {
            crystlToken = await ethers.getContractAt(token_abi, CRYSTL);
            userRewardTokenBalanceBeforeWithdrawal = await crystlToken.balanceOf(user1.address);

            await vaultHealer.connect(user1)["harvestBoost(uint256,uint256)"](strat1_pid, 0);
            
            userRewardTokenBalanceAfterWithdrawal = await crystlToken.balanceOf(user1.address);
            expect(userRewardTokenBalanceAfterWithdrawal.sub(userRewardTokenBalanceBeforeWithdrawal)).to.be.gt(0); //eq(userRewardDebtAfterTime.add(1000000)); //adding one extra block of reward - this right?

        })

        //check that reward got returned to user1 on withdrawal

        // it('should return reward to user upon unstaking', async () => {
        //     // userRewardDebtBeforeWithdrawal = await boostPool.pendingReward(user1.address);
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
        })
        
        // Unstake 50% of LPs. 
        // Check transaction to ensure withdraw fee amount is as expected and amount withdrawn in as expected
        it('Should withdraw 50% of LPs with correct withdraw fee amount (0.1%) and decrease users stakedWantTokens balance correctly', async () => {
            const LPtokenBalanceBeforeFirstWithdrawal = await LPtoken.balanceOf(user1.address);
            const UsersStakedTokensBeforeFirstWithdrawal = await vaultHealerView.stakedWantTokens(strat1_pid, user1.address);
            console.log(ethers.utils.formatEther(LPtokenBalanceBeforeFirstWithdrawal));
            console.log(ethers.utils.formatEther(UsersStakedTokensBeforeFirstWithdrawal));

            vaultSharesTotalInMaximizerBeforeWithdraw = await strategyVHStandard.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            console.log(ethers.utils.formatEther(vaultSharesTotalInMaximizerBeforeWithdraw));

            crystlToken = await ethers.getContractAt(token_abi, CRYSTL);
            user1CrystlBalanceBeforeWithdraw = await crystlToken.balanceOf(user1.address);

            console.log(`User 1 withdraws ${ethers.utils.formatEther(UsersStakedTokensBeforeFirstWithdrawal.div(2))} LP tokens from the vault`)

            await vaultHealer["withdraw(uint256,uint256)"](strat1_pid, UsersStakedTokensBeforeFirstWithdrawal.div(2)); 
            
            const LPtokenBalanceAfterFirstWithdrawal = await LPtoken.balanceOf(user1.address);
            console.log(ethers.utils.formatEther(LPtokenBalanceAfterFirstWithdrawal));

            // vaultSharesTotalAfterFirstWithdrawal = await strategyVHStandard.connect(vaultHealerOwnerSigner).vaultSharesTotal() 
            const UsersStakedTokensAfterFirstWithdrawal = await vaultHealerView.stakedWantTokens(strat1_pid, user1.address);

            // console.log(ethers.utils.formatEther(vaultSharesTotalInMaximizerBeforeWithdraw));
            // console.log(ethers.utils.formatEther(vaultSharesTotalAfterFirstWithdrawal));
            console.log(`We now have ${ethers.utils.formatEther(UsersStakedTokensAfterFirstWithdrawal)} total LP tokens left in the vault`)
            // console.log(await vaultHealer.userTotals(strat1_pid, user1.address));

            expect(LPtokenBalanceAfterFirstWithdrawal.sub(LPtokenBalanceBeforeFirstWithdrawal))
            .to.equal(
                (UsersStakedTokensBeforeFirstWithdrawal.div(2))
                    .sub((WITHDRAW_FEE_FACTOR_MAX.sub(withdrawFeeFactor))
                    .mul(UsersStakedTokensBeforeFirstWithdrawal.div(2))
                    .div(WITHDRAW_FEE_FACTOR_MAX))
                )
                ;
        })

                // Stake a round number of LPs (e.g., 1 or 0.0001) - not a round number yet!
        it('Should deposit 1500 of user2\'s LP tokens into the vault, increasing users stakedWantTokens by the correct amount', async () => {
            // const LPtokenBalanceOfUser2BeforeFirstDeposit = await LPtoken.balanceOf(user2.address);
            user2InitialDeposit = ethers.utils.parseEther("1500");
            const vaultSharesTotalBeforeUser2FirstDeposit = await strategyVHStandard.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            console.log(`VaultSharesTotal is ${ethers.utils.formatEther(vaultSharesTotalBeforeUser2FirstDeposit)} LP tokens before user 2 deposits`)

            await LPtoken.connect(user2).approve(vaultHealer.address, user2InitialDeposit); //no, I have to approve the vaulthealer surely?
            // console.log("lp token approved by user 2")
            await vaultHealer.connect(user2)["deposit(uint256,uint256)"](strat1_pid, user2InitialDeposit);
            const vaultSharesTotalAfterUser2FirstDeposit = await strategyVHStandard.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            const User2sStakedTokensAfterFirstDeposit = await vaultHealerView.stakedWantTokens(strat1_pid, user2.address);
            console.log(`User2 has ${ethers.utils.formatEther(User2sStakedTokensAfterFirstDeposit)} after making their first deposit`)

            console.log(`User 2 deposits ${ethers.utils.formatEther(user2InitialDeposit)} LP tokens`)
            console.log(`VaultSharesTotal is ${ethers.utils.formatEther(vaultSharesTotalAfterUser2FirstDeposit)} LP tokens after user 2 deposits`)

            expect(user2InitialDeposit).to.equal(User2sStakedTokensAfterFirstDeposit) //.sub(vaultSharesTotalBeforeUser2FirstDeposit)); //will this work for 2nd deposit? on normal masterchef?
        })

        // Deposit 100% of users LP tokens into vault, ensure balance increases as expected.
        it('Should accurately increase users shares upon second deposit by user1', async () => {
            const LPtokenBalanceBeforeSecondDeposit = await LPtoken.balanceOf(user1.address);
            await LPtoken.approve(vaultHealer.address, LPtokenBalanceBeforeSecondDeposit);
            const User1sStakedTokensBeforeSecondDeposit = await vaultHealerView.stakedWantTokens(strat1_pid, user1.address);

            await vaultHealer["deposit(uint256,uint256)"](strat1_pid, LPtokenBalanceBeforeSecondDeposit); //user1 (default signer) deposits LP tokens into specified strat1_pid vaulthealer
            
            const LPtokenBalanceAfterSecondDeposit = await LPtoken.balanceOf(user1.address);
            const User1sStakedTokensAfterSecondDeposit = await vaultHealerView.stakedWantTokens(strat1_pid, user1.address);

            expect(LPtokenBalanceBeforeSecondDeposit.sub(LPtokenBalanceAfterSecondDeposit)).to.closeTo(User1sStakedTokensAfterSecondDeposit.sub(User1sStakedTokensBeforeSecondDeposit), ethers.BigNumber.from(1000000000000000)); //will this work for 2nd deposit? on normal masterchef?
        })
        

        // Withdraw 100%
        it('Should withdraw remaining user1 balance back to user1, with all of it staked in boosting pool, minus withdrawal fee (0.1%)', async () => {
            userBalanceOfStrategyTokensBeforeStaking = await vaultHealer.balanceOf(user1.address, strat1_pid);

            //Should not use approval in this manner ever
            //await vaultHealer.connect(user1).setApprovalForAll(boostPool.address, true); //dangerous to approve all forever?

            //await vaultHealer.connect(user1)["enableBoost(uint256,uint256)"](strat1_pid, 0);
            user = await boostPool.userInfo(user1.address);
            userBalanceOfBoostPool = user.amount;

            userWantTokensBeforeWithdrawal = await vaultHealerView.stakedWantTokens(strat1_pid, user1.address);
            const LPtokenBalanceBeforeFinalWithdrawal = await LPtoken.balanceOf(user1.address)
            console.log("userWantTokensBeforeWithdrawal");
            console.log(userWantTokensBeforeWithdrawal);

            console.log("LPtokenBalanceBeforeFinalWithdrawal - user1")
            console.log(ethers.utils.formatEther(LPtokenBalanceBeforeFinalWithdrawal))

            const UsersStakedTokensBeforeFinalWithdrawal = await vaultHealerView.stakedWantTokens(strat1_pid, user1.address);
            console.log("UsersStakedTokensBeforeFinalWithdrawal - user1")
            console.log(ethers.utils.formatEther(UsersStakedTokensBeforeFinalWithdrawal))
            // userBoostedWantTokensBeforeWithdrawal = await vaultHealerView.stakedWantTokens(strat1_pid, user1.address);
            // console.log("userBoostedWantTokensBeforeWithdrawal");
            // console.log(ethers.utils.formatEther(userBoostedWantTokensBeforeWithdrawal));

            await vaultHealer["withdrawAll(uint256)"](strat1_pid); //+userBoostedWantTokensBeforeWithdrawal user1 (default signer) deposits 1 of LP tokens into strat1_pid 0 of vaulthealer
            
            const LPtokenBalanceAfterFinalWithdrawal = await LPtoken.balanceOf(user1.address);
            console.log("LPtokenBalanceAfterFinalWithdrawal - user1")
            console.log(ethers.utils.formatEther(LPtokenBalanceAfterFinalWithdrawal))

            UsersStakedTokensAfterFinalWithdrawal = await vaultHealerView.stakedWantTokens(strat1_pid, user1.address);
            console.log("UsersStakedTokensAfterFinalWithdrawal - user1")
            console.log(ethers.utils.formatEther(UsersStakedTokensAfterFinalWithdrawal))
            
            userBoostedWantTokensAfterWithdrawal = await vaultHealerView.stakedWantTokens(strat1_pid, user1.address); //todo change to boosted tokens??
            console.log(withdrawFeeFactor);
            console.log(WITHDRAW_FEE_FACTOR_MAX);

            expect(LPtokenBalanceAfterFinalWithdrawal.sub(LPtokenBalanceBeforeFinalWithdrawal))
            .to.closeTo(
                (UsersStakedTokensBeforeFinalWithdrawal.sub(UsersStakedTokensAfterFinalWithdrawal)) //.add(userBoostedWantTokensBeforeWithdrawal).sub(userBoostedWantTokensAfterWithdrawal))
                .sub(
                    (WITHDRAW_FEE_FACTOR_MAX.sub(withdrawFeeFactor))
                    .mul(UsersStakedTokensBeforeFinalWithdrawal.sub(UsersStakedTokensAfterFinalWithdrawal)) //.add(userBoostedWantTokensBeforeWithdrawal).sub(userBoostedWantTokensAfterWithdrawal))
                    .div(WITHDRAW_FEE_FACTOR_MAX),
                ),
				ethers.BigNumber.from(1000000000000000)
                );
        })

        //ensure no funds left in the vault.
        it('Should leave zero user1 funds in vault after 100% withdrawal', async () => {
            // console.log(await crystlToken.balanceOf(strategyVHStandard.address))
            expect(UsersStakedTokensAfterFinalWithdrawal).to.equal(0);
        })

        it('Should leave zero user1 funds in boostPool after 100% withdrawal', async () => {
            // console.log(await crystlToken.balanceOf(strategyVHStandard.address))
            user = await boostPool.userInfo(user1.address);
            userBalanceOfBoostPoolAtEnd = user.amount;
            expect(userBalanceOfBoostPoolAtEnd).to.equal(0);
        })
        
    })
})

