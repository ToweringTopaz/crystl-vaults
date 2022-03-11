// import hre from "hardhat";

const { tokens, accounts, routers } = require('../configs/addresses.js');
const { WMATIC, CRYSTL, DAI, USDC } = tokens.polygon;
const { FEE_ADDRESS, BURN_ADDRESS, ZERO_ADDRESS } = accounts.polygon;
const { expect } = require('chai');
const { ethers } = require('hardhat');
const { IUniRouter02_abi } = require('./abi_files/IUniRouter02_abi.js');
const { token_abi } = require('./abi_files/token_abi.js');
const { IWETH_abi } = require('./abi_files/IWETH_abi.js');
const { IUniswapV2Pair_abi } = require('./abi_files/IUniswapV2Pair_abi.js');
const { getContractAddress } = require('@ethersproject/address')

//////////////////////////////////////////////////////////////////////////
// THESE FIVE VARIABLES BELOW NEED TO BE SET CORRECTLY FOR A GIVEN TEST //
//////////////////////////////////////////////////////////////////////////

const STRATEGY_CONTRACT_TYPE = 'Strategy'; //<-- change strategy type to the contract deployed for this strategy
const { apeSwapVaults } = require('../configs/apeSwapVaults.js'); //<-- replace all references to 'dinoswapVaults' (for example), with the right '...Vaults' name

const MASTERCHEF = apeSwapVaults[1].masterchef;
const VAULT_HEALER = apeSwapVaults[1].vaulthealer;
const WANT = apeSwapVaults[1].want;
const EARNED = apeSwapVaults[1].earned;
const PID = apeSwapVaults[1].PID;
const TARGET_WANT_ROUTER = routers.polygon.APESWAP_ROUTER;
const LP_AND_EARN_ROUTER = apeSwapVaults[1].router;

const EARNED_TOKEN_1 = EARNED[0]
const EARNED_TOKEN_2 = EARNED[1]
//const minBlocksBetweenSwaps = 100;

describe(`Testing ${STRATEGY_CONTRACT_TYPE} contract with the following variables:
    connected to vaultHealer @  ${VAULT_HEALER}
    depositing these LP tokens: ${WANT}
    into Masterchef:            ${MASTERCHEF} 
    with earned token:          ${EARNED_TOKEN_1}
    with earned2 token:         ${EARNED_TOKEN_2}
    `, () => {
    before(async () => {
        [user1, user2, user3, user4, _] = await ethers.getSigners();
		
		Magnetite = await ethers.getContractFactory("Magnetite");
		magnetite = await Magnetite.deploy();
		
        const from = user1.address;
        const nonce = 1 + await user1.getTransactionCount();
		// vaultHealer = await getContractAddress({from, nonce});
		withdrawFee = ethers.BigNumber.from(10);
        earnFee = ethers.BigNumber.from(500);
		VaultFeeManager = await ethers.getContractFactory("VaultFeeManager");
		vaultFeeManager = await VaultFeeManager.deploy(await getContractAddress({from, nonce}), FEE_ADDRESS, withdrawFee, [ FEE_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS ], [earnFee, 0, 0]);
        VaultHealer = await ethers.getContractFactory("VaultHealer");
        vaultHealer = await VaultHealer.deploy("", ZERO_ADDRESS, user1.address, vaultFeeManager.address);
		
        vaultHealer.on("FailedEarn", (vid, reason) => {
			console.log("FailedEarn: ", vid, reason);
		});
		vaultHealer.on("FailedEarnBytes", (vid, reason) => {
			console.log("FailedEarnBytes: ", vid, reason);
		});
		
		//DINO to MATIC
		magnetite.overridePath(LP_AND_EARN_ROUTER, [ '0xaa9654becca45b5bdfa5ac646c939c62b527d394', '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174', '0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270' ]);
		//DINO to WETH
		magnetite.overridePath(LP_AND_EARN_ROUTER, [ '0xaa9654becca45b5bdfa5ac646c939c62b527d394', '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174', '0x7ceb23fd6bc0add59e62ac25578270cff1b9f619' ]);


        //create the factory for the strategy implementation contract
        Strategy = await ethers.getContractFactory('Strategy');
        //deploy the strategy implementation contract
		strategyImplementation = await Strategy.deploy(vaultHealer.address);

        //create the factory for the tactics implementation contract
        Tactics = await ethers.getContractFactory("Tactics");
        //deploy the tactics contract for this specific type of strategy (e.g. masterchef, stakingRewards, or miniChef)
        tactics = await Tactics.deploy()
		let [tacticsA, tacticsB] = await tactics.generateTactics(
			apeSwapVaults[1]['masterchef'],
            apeSwapVaults[1]['PID'],
            0, //position of return value in vaultSharesTotal returnData array - have to look at contract and see
            ethers.BigNumber.from("0x93f1a40b23000000"), //includes selector and encoded call format
            ethers.BigNumber.from("0x8dbdbe6d24300000"), //includes selector and encoded call format
            ethers.BigNumber.from("0x0ad58d2f24300000"), //includes selector and encoded call format
            ethers.BigNumber.from("0x18fccc7623000000"), //includes selector and encoded call format
            ethers.BigNumber.from("0x2f940c7023000000") //includes selector and encoded call format
        );

        //create factory and deploy strategyConfig contract
        StrategyConfig = await ethers.getContractFactory("StrategyConfig");
        strategyConfig = await StrategyConfig.deploy()
        console.log("strategyConfig deployed");

        DEPLOYMENT_DATA = await strategyConfig.generateConfig(
            tacticsA,
			tacticsB,
			apeSwapVaults[1]['want'],
			apeSwapVaults[1]['wantDust'],
			LP_AND_EARN_ROUTER, //note this has to be specified at deployment time
			magnetite.address,
			240, //slippageFactor
			false, //feeOnTransfer
			apeSwapVaults[1]['earned'],
			apeSwapVaults[1]['earnedDust'],
		);
        
        LPtoken = await ethers.getContractAt(IUniswapV2Pair_abi, WANT);
        TOKEN0ADDRESS = await LPtoken.token0()
        console.log(TOKEN0ADDRESS)
        TOKEN1ADDRESS = await LPtoken.token1()
        console.log(TOKEN1ADDRESS)

        TOKEN_OTHER = USDC;

        let [crystlTacticsA, crystlTacticsB] = await tactics.generateTactics(
			apeSwapVaults[0]['masterchef'],
            apeSwapVaults[0]['PID'],
            0, //position of return value in vaultSharesTotal returnData array - have to look at contract and see
            ethers.BigNumber.from("0x93f1a40b23000000"), //includes selector and encoded call format
            ethers.BigNumber.from("0x8dbdbe6d24300000"), //includes selector and encoded call format
            ethers.BigNumber.from("0x0ad58d2f24300000"), //includes selector and encoded call format
            ethers.BigNumber.from("0x18fccc7623000000"), //includes selector and encoded call format
            ethers.BigNumber.from("0x2f940c7023000000") //includes selector and encoded call format
        );

		TARGET_WANT_COMPOUNDER_DATA = await strategyConfig.generateConfig(
            crystlTacticsA,
			crystlTacticsB,
			apeSwapVaults[0]['want'],
			apeSwapVaults[0]['wantDust'],
			LP_AND_EARN_ROUTER, //note this has to be specified at deployment time
			magnetite.address,
			240, //slippageFactor
			false, //feeOnTransfer
			apeSwapVaults[0]['earned'],
			apeSwapVaults[0]['earnedDust'],
		);
		
		TARGET_WANT = await ethers.getContractAt(token_abi, apeSwapVaults[0]['want']);		
		console.log("cc stratconfig generated");

        vaultHealerOwnerSigner = user1
        
        zapAddress = await vaultHealer.zap()

		quartzUniV2Zap = await ethers.getContractAt('QuartzUniV2Zap', await vaultHealer.zap());
       
		await vaultHealer.connect(vaultHealerOwnerSigner).createVault(strategyImplementation.address, DEPLOYMENT_DATA);
		strat1_pid = await vaultHealer.numVaultsBase();
		strat1 = await ethers.getContractAt('Strategy', await vaultHealer.strat(strat1_pid))
        console.log("strat1 address: ",strat1.address);

		await vaultHealer.connect(vaultHealerOwnerSigner).createVault(strategyImplementation.address, TARGET_WANT_COMPOUNDER_DATA);
        crystl_compounder_strat_pid = await vaultHealer.numVaultsBase();
        strategyCrystlCompounder = await ethers.getContractAt('Strategy', await vaultHealer.strat(crystl_compounder_strat_pid));
		console.log("strategyCrystlCompounder address: ", strategyCrystlCompounder.address);

		MAXIMIZER_DATA = DEPLOYMENT_DATA;
		console.log("maxi config generated");

        maximizer_strat_pid = (crystl_compounder_strat_pid << 16) + 1 //we start at 1, not zero, numbering the maximizers for a given pool

		await vaultHealer.connect(vaultHealerOwnerSigner).createMaximizer(crystl_compounder_strat_pid, MAXIMIZER_DATA);
        strategyMaximizer = await ethers.getContractAt('Strategy', await vaultHealer.strat(maximizer_strat_pid));
        console.log("strategyMaximizer address: ", strategyMaximizer.address);

        //create the staking pool for the boosted vault
        BoostPoolImplementation = await ethers.getContractFactory("BoostPool", {});
        //need the wantToken address from the strategy!
		
        boostPoolImplementation = await BoostPoolImplementation.deploy(vaultHealer.address)
		abiCoder = new ethers.utils.AbiCoder()
		
		BOOST_POOL_DATA = abiCoder.encode(["address", "uint112", "uint32", "uint32"], [
		    "0x76bf0c28e604cc3fe9967c83b3c3f31c213cfe64", //reward token = crystl
            1000000, //is this in WEI? assume so...
            0,
            640515
		]);
		
		boostID = strat1_pid
		boostPool = await vaultHealer.boostPool(boostID);

		targetRouter = await ethers.getContractAt(IUniRouter02_abi, TARGET_WANT_ROUTER);
        await targetRouter.swapExactETHForTokens(0, [WMATIC, CRYSTL], boostPool, Date.now() + 900, { value: ethers.utils.parseEther("45") })

		await vaultHealer.createBoost(
		    strat1_pid,
			boostPoolImplementation.address,
			BOOST_POOL_DATA
		);
		
        // find users 1 through 4 with MATIC
        users = [user1, user2, user3, user4]
        for (let x of users) {
            await network.provider.send("hardhat_setBalance", [
                x.address,
                "0x21E19E0C9BAB240000000", //amount of 2560000*10^18 in hex
            ]);
        }
	
        //create a router to swap into the underlying tokens for the LP and then add liquidity
        LPandEarnRouter = await ethers.getContractAt(IUniRouter02_abi, LP_AND_EARN_ROUTER);
        WNATIVE = await LPandEarnRouter.WETH();
        tokenAddressList = [TOKEN0ADDRESS, TOKEN1ADDRESS, CRYSTL, WNATIVE];

        // for each of users 1 through 4, swap from MATIC into TOKEN0 and TOKEN1
        for (let user of users) {
            for (let tokenAddress of tokenAddressList) {
                if (ethers.utils.getAddress(tokenAddress) == ethers.utils.getAddress(WNATIVE)) {
                    wmatic_token = await ethers.getContractAt(IWETH_abi, tokenAddress); 
                    await wmatic_token.connect(user).deposit({ value: ethers.utils.parseEther("1000") });
                } else {
                    await LPandEarnRouter.connect(user).swapExactETHForTokens(0, [WNATIVE, tokenAddress], user.address, Date.now() + 900, { value: ethers.utils.parseEther("1000") })
                }
            }   
        }

        await targetRouter.connect(user4).swapExactETHForTokens(0, [WMATIC, TOKEN_OTHER], user4.address, Date.now() + 900, { value: ethers.utils.parseEther("50000") }) //USDC 6 decimals
        TARGET_WANT_UNDERLYING0 = WMATIC
        TARGET_WANT_UNDERLYING1 = CRYSTL
        targetUnderlyingList = [TARGET_WANT_UNDERLYING0, TARGET_WANT_UNDERLYING1]
        
        for (tokenAddress of targetUnderlyingList) {
            if (ethers.utils.getAddress(tokenAddress) == ethers.utils.getAddress(WNATIVE)) {
                wmatic_token = await ethers.getContractAt(IWETH_abi, tokenAddress); 
                await wmatic_token.connect(user4).deposit({ value: ethers.utils.parseEther("1000") });
            } else {
                await LPandEarnRouter.connect(user4).swapExactETHForTokens(0, [WNATIVE, tokenAddress], user4.address, Date.now() + 900, { value: ethers.utils.parseEther("1000") })
            }
        }  

        // await targetRouter.connect(user4).swapExactETHForTokens(0, [WMATIC, CRYSTL], user4.address, Date.now() + 900, { value: ethers.utils.parseEther("50000") })

        //create instances of token0 and token1
        token0 = await ethers.getContractAt(token_abi, TOKEN0ADDRESS);
        token1 = await ethers.getContractAt(token_abi, TOKEN1ADDRESS);
        console.log("created token instances")
        
        // get approvals for users 1 through 3 for tokens 0 and 1
        threeUsers = [user1, user2, user3];
        tokenInstanceList = [token0, token1];
        for (user of threeUsers) {
            for (let tokenInstance of tokenInstanceList) {
                var tempBalance = await tokenInstance.balanceOf(user.address);
                await tokenInstance.connect(user).approve(LPandEarnRouter.address, tempBalance);
            }
        }

        // add liquidity for users 1 through 3, to get LP tokens
        for (user of threeUsers) {
            await LPandEarnRouter.connect(user).addLiquidity(
                TOKEN0ADDRESS, 
                TOKEN1ADDRESS, 
                await token0.balanceOf(user.address), 
                await token1.balanceOf(user.address), 
                0, 
                0, 
                user.address, Date.now() + 900
                )
        }

        //create instances of targetUnderlying1 and targetUnderlying2
        targetUnderlying0 = await ethers.getContractAt(token_abi, TARGET_WANT_UNDERLYING0);
        targetUnderlying1 = await ethers.getContractAt(token_abi, TARGET_WANT_UNDERLYING1);
        targetUnderlyingInstanceList = [targetUnderlying0, targetUnderlying1];

        // get approvals for users 1 through 3 for tokens 0 and 1
        for (let tokenInstance of targetUnderlyingInstanceList) {
            var tempBalance = await tokenInstance.balanceOf(user4.address);
            await tokenInstance.connect(user4).approve(LPandEarnRouter.address, tempBalance);
        }
        console.log("got here")
        //add liquidity for user4 of TARGET_WANT tokens
        await LPandEarnRouter.connect(user4).addLiquidity(
            TARGET_WANT_UNDERLYING0, 
            TARGET_WANT_UNDERLYING1, 
            await targetUnderlying0.balanceOf(user4.address), 
            await targetUnderlying1.balanceOf(user4.address), 
            0, 
            0, 
            user4.address, Date.now() + 900
            )
        console.log("got here")
        tokenOther = await ethers.getContractAt(token_abi, TOKEN_OTHER);
        //TARGET_WANT = await ethers.getContractAt(token_abi, CRYSTL);

    });
	
    describe(`Testing depositing into maximizer vault, compounding maximizer vault, withdrawing from maximizer vault:
    `, () => {
        //user zaps in their whole token0 balance
         it('Should zap token0 into the vault (convert to underlying, add liquidity, and deposit to vault) - leading to an increase in vaultSharesTotal', async () => {
             token0 = await ethers.getContractAt(token_abi, TOKEN0ADDRESS);

             var token0Balance = await token0.balanceOf(user4.address);
             await token0.connect(user4).approve(quartzUniV2Zap.address, token0Balance);

             const vaultSharesTotalBeforeFirstZap = await strategyMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0

             await quartzUniV2Zap.connect(user4).quartzIn(maximizer_strat_pid, 0, token0.address, token0Balance); //todo - change min in amount from 0

             const vaultSharesTotalAfterFirstZap = await strategyMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0

             expect(vaultSharesTotalAfterFirstZap).to.be.gt(vaultSharesTotalBeforeFirstZap);
         })
        
         //user zaps in their whole token1 balance
         it('Should zap token1 into the vault (convert to underlying, add liquidity, and deposit to vault) - leading to an increase in vaultSharesTotal', async () => {
             token1 = await ethers.getContractAt(token_abi, TOKEN1ADDRESS);
             var token1Balance = await token1.balanceOf(user4.address);
             await token1.connect(user4).approve(quartzUniV2Zap.address, token1Balance);
            
             const vaultSharesTotalBeforeSecondZap = await strategyMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0

             await quartzUniV2Zap.connect(user4).quartzIn(maximizer_strat_pid, 0, token1.address, token1Balance); //To Do - change min in amount from 0
            
             const vaultSharesTotalAfterSecondZap = await strategyMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0

             expect(vaultSharesTotalAfterSecondZap).to.be.gt(vaultSharesTotalBeforeSecondZap);
         })

        //user zaps in their whole balance of token_other
        it('Should zap a token that is neither token0 nor token1 into the vault (convert to underlying, add liquidity, and deposit to vault) - leading to an increase in vaultSharesTotal', async () => {
            // assume(TOKEN_OTHER != TOKEN0 && TOKEN_OTHER != TOKEN1);
            user4TokenOtherDepositAmount = ethers.utils.parseUnits("100", "mwei"); //USDC is 6 decimals

            await tokenOther.connect(user4).approve(quartzUniV2Zap.address, user4TokenOtherDepositAmount);
            
            const vaultSharesTotalBeforeThirdZap = await strategyMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0

            await quartzUniV2Zap.connect(user4).quartzIn(maximizer_strat_pid, 0, tokenOther.address, user4TokenOtherDepositAmount); //To Do - change min in amount from 0
            
            const vaultSharesTotalAfterThirdZap = await strategyMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0

            expect(vaultSharesTotalAfterThirdZap).to.be.gt(vaultSharesTotalBeforeThirdZap);
        })

        it('Zap out should withdraw LP tokens from vault, convert back to underlying tokens, and send back to user, increasing their token0 and token1 balances', async () => {
            const vaultSharesTotalBeforeZapOut = await strategyMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal();
            var token0BalanceBeforeZapOut;
            var token0BalanceAfterZapOut;
            var token1BalanceBeforeZapOut;
            var token1BalanceAfterZapOut;

            if (TOKEN0ADDRESS == ethers.utils.getAddress(WNATIVE) ){
                token0BalanceBeforeZapOut = await ethers.provider.getBalance(user4.address);
            } else {
                token0BalanceBeforeZapOut = await token0.balanceOf(user4.address); 
            }

            if (TOKEN1ADDRESS == ethers.utils.getAddress(WNATIVE) ){
                token1BalanceBeforeZapOut = await ethers.provider.getBalance(user4.address);
            } else {
                token1BalanceBeforeZapOut = await token1.balanceOf(user4.address); 
            }

            await quartzUniV2Zap.connect(user4).quartzOut(maximizer_strat_pid, vaultSharesTotalBeforeZapOut); 
                        
            if (TOKEN0ADDRESS == ethers.utils.getAddress(WNATIVE) ){
                token0BalanceAfterZapOut = await ethers.provider.getBalance(user4.address);
            } else {
                token0BalanceAfterZapOut = await token0.balanceOf(user4.address); 
            }

            if (TOKEN1ADDRESS == ethers.utils.getAddress(WNATIVE) ){
                token1BalanceAfterZapOut = await ethers.provider.getBalance(user4.address);
            } else {
                token1BalanceAfterZapOut = await token1.balanceOf(user4.address); 
            }

            expect(token0BalanceAfterZapOut).to.be.gt(token0BalanceBeforeZapOut); //todo - change to check before and after zap out rather
            expect(token1BalanceAfterZapOut).to.be.gt(token1BalanceBeforeZapOut); //todo - change to check before and after zap out rather

        })

        //user should have positive balances of token0 and token1 after zap out (note - if one of the tokens is wmatic it gets paid back as matic...)
        it('Should leave user with positive balance of token0', async () => {
            var token0Balance;

            if (TOKEN0ADDRESS == ethers.utils.getAddress(WNATIVE) ){
                token0Balance = await ethers.provider.getBalance(user4.address);
            } else {
                token0Balance = await token0.balanceOf(user4.address); 
            }

            expect(token0Balance).to.be.gt(0); //todo - change to check before and after zap out rather
        })

        //user should have positive balances of token0 and token1 after zap out (note - if one of the tokens is wmatic it gets paid back as matic...)
        it('Should leave user with positive balance of token1', async () => {
            var token1Balance;

            if (TOKEN1ADDRESS == ethers.utils.getAddress(WNATIVE) ){
                token1Balance = await ethers.provider.getBalance(user4.address);
            } else {
                token1Balance = await token1.balanceOf(user4.address); 
            }

            expect(token1Balance).to.be.gt(0);
        })

        //ensure no funds left in the vault after zap out
        it('Should leave zero user funds in vault after 100% zap out', async () => {
            UsersStakedTokensAfterZapOut = await vaultHealer.balanceOf(user4.address, maximizer_strat_pid);
            expect(UsersStakedTokensAfterZapOut.toNumber()).to.equal(0);
        })

        //ensure no funds left in the vault after zap out
        it('Should leave vaultSharesTotal at zero after 100% zap out', async () => {
            vaultSharesTotalAfterZapOut = await strategyMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal();
            expect(vaultSharesTotalAfterZapOut.toNumber()).to.equal(0);
        })

        it('Should deposit user1\'s 5000 LP tokens into the vault, increasing vaultSharesTotal by the correct amount', async () => {
            // initialLPtokenBalance = await LPtoken.balanceOf(user1.address);
            user1InitialDeposit = (await LPtoken.balanceOf(user1.address)).div(2); //ethers.utils.parseEther("100");
			
            // await LPandEarnRouter.swapExactETHForTokens(0, [WNATIVE, CRYSTL], user1.address, Date.now() + 900, { value: ethers.utils.parseEther("4500") })
			// token0 = await ethers.getContractAt(token_abi, TOKEN0ADDRESS);
            // await TARGET_WANT.approve(vaultHealer.address, user1InitialDeposit);
            
            await LPtoken.approve(vaultHealer.address, user1InitialDeposit);
            const vaultSharesTotalBeforeFirstDeposit = await strategyMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0

            LPtokenBalanceBeforeFirstDeposit = await LPtoken.balanceOf(user1.address);
            await vaultHealer["deposit(uint256,uint256)"](maximizer_strat_pid, user1InitialDeposit);
            const vaultSharesTotalAfterFirstDeposit = await strategyMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            console.log(`User1 deposits ${ethers.utils.formatEther(user1InitialDeposit)} LP tokens`)
            console.log(`Vault Shares Total went up by ${ethers.utils.formatEther(vaultSharesTotalAfterFirstDeposit)} LP tokens`)

            expect(user1InitialDeposit).to.equal(vaultSharesTotalAfterFirstDeposit.sub(vaultSharesTotalBeforeFirstDeposit));
        })
        
        it('Should mint ERC1155 tokens for this user, with the maximizer_strat_pid of the strategy and equal to LP tokens deposited', async () => {
            userBalanceOfStrategyTokens = await vaultHealer.balanceOf(user1.address, maximizer_strat_pid);
            console.log(`User1 balance of ERC1155 tokens is now ${ethers.utils.formatEther(userBalanceOfStrategyTokens)} tokens`)
            expect(userBalanceOfStrategyTokens).to.eq(user1InitialDeposit); 
        })

        // Compound LPs (Call the earn function with this specific farm’s maximizer_strat_pid).
        // Check balance to ensure it increased as expected
        it('Should wait 10 blocks, then compound the maximizer vault by calling earn(), resulting in an increase in maxiTarget in the maxiTarget compounder', async () => {
            const vaultSharesTotalBeforeCallingEarn = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            console.log(`We start with ${ethers.utils.formatEther(vaultSharesTotalBeforeCallingEarn)} crystl tokens in the maxiTarget compounder`)
            console.log(`We let 100 blocks pass, and then call earn...`)

            balanceMaticAtFeeAddressBeforeEarn = await ethers.provider.getBalance(FEE_ADDRESS); //note: MATIC, not WMATIC

            // console.log(`Block number before calling earn ${await ethers.provider.getBlockNumber()}`)
            // console.log(`vaultSharesTotalBeforeCallingEarn: ${vaultSharesTotalBeforeCallingEarn}`)

            for (i=0; i<5000;i++) { //minBlocksBetweenSwaps - can use this variable as an alternate to hardcoding a value
                await ethers.provider.send("evm_mine"); //creates a delay of 100 blocks - could adjust this to be minBlocksBetweenSwaps+1 blocks
            }

            await vaultHealer["earn(uint256[])"]([maximizer_strat_pid]);
            // console.log(`Block number after calling earn ${await ethers.provider.getBlockNumber()}`)

            vaultSharesTotalAfterCallingEarn = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            console.log(`After the earn call we have ${ethers.utils.formatEther(vaultSharesTotalAfterCallingEarn)} maxiTarget tokens in the maxiTarget compounder`)
            // console.log(await vaultHealer.userTotals(maximizer_strat_pid, user1.address));

            expect(vaultSharesTotalAfterCallingEarn).to.be.gt(vaultSharesTotalBeforeCallingEarn); //.toNumber()
        }) 

        it('Should pay 5% of earnedAmt to the feeAddress with each earn, in MATIC', async () => {
            balanceMaticAtFeeAddressAfterEarn = await ethers.provider.getBalance(FEE_ADDRESS); //note: MATIC, not WMATIC
            console.log(`MATIC at Fee Address went up by ${ethers.utils.formatEther(balanceMaticAtFeeAddressAfterEarn.sub(balanceMaticAtFeeAddressBeforeEarn))} tokens`)
            expect(balanceMaticAtFeeAddressAfterEarn).to.be.gt(balanceMaticAtFeeAddressBeforeEarn);
        })

        // Compound LPs (Call the earn function with this specific farm’s maximizer_strat_pid).
        // Check balance to ensure it increased as expected
        it('Should wait 10 blocks, then compound the maxiTarget Compounder by calling earn(), so that vaultSharesTotal is greater after than before', async () => {
            const vaultSharesTotalBeforeCallingEarn = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            const wantLockedTotalBeforeCallingEarn = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).wantLockedTotal()

            console.log(`Before calling earn on the maxiTarget compounder, we have ${ethers.utils.formatEther(vaultSharesTotalBeforeCallingEarn)} maxiTarget tokens in it`)
            console.log(`We let 100 blocks pass...`)
            // console.log(`Block number before calling earn ${await ethers.provider.getBlockNumber()}`)
            console.log(`vaultSharesTotalBeforeCallingEarn: ${vaultSharesTotalBeforeCallingEarn}`)

            for (i=0; i<5000;i++) { //minBlocksBetweenSwaps - can use this variable as an alternate to hardcoding a value
                await ethers.provider.send("evm_mine"); //creates a delay of 100 blocks - could adjust this to be minBlocksBetweenSwaps+1 blocks
            }

            await vaultHealer["earn(uint256[])"]([crystl_compounder_strat_pid]);
            // console.log(`Block number after calling earn ${await ethers.provider.getBlockNumber()}`)

            vaultSharesTotalInCrystalCompounderAfterCallingEarn = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            console.log(`vaultSharesTotalInCrystalCompounderAfterCallingEarn: ${vaultSharesTotalInCrystalCompounderAfterCallingEarn}`)
            console.log(`After calling earn on the maxiTarget compounder, we have ${ethers.utils.formatEther(vaultSharesTotalInCrystalCompounderAfterCallingEarn)} maxiTarget tokens in it`)
            // console.log(await vaultHealer.userTotals(maximizer_strat_pid, user1.address));

            expect(vaultSharesTotalInCrystalCompounderAfterCallingEarn).to.be.gt(vaultSharesTotalBeforeCallingEarn); //.toNumber()
        }) 
        
        // Unstake 50% of LPs. 
        // Check transaction to ensure withdraw fee amount is as expected and amount withdrawn in as expected
        it('Should withdraw 50% of user 1 LPs with correct withdraw fee amount (0.1%) and decrease user\'s balance correctly', async () => {
            const LPtokenBalanceBeforeFirstWithdrawal = await LPtoken.balanceOf(user1.address);
            const UsersSharesBeforeFirstWithdrawal = await vaultHealer.balanceOf(user1.address, maximizer_strat_pid);

            vaultSharesTotalInMaximizerBeforeWithdraw = await strategyMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            user1CrystlBalanceBeforeWithdraw = await TARGET_WANT.balanceOf(user1.address);
			user1CrystlShareBalanceBeforeWithdraw = await vaultHealer.balanceOf(user1.address, crystl_compounder_strat_pid);
//			user1CrystlShareRawBalanceBeforeWithdraw = await vaultHealer.rawBalanceOf(user1.address, crystl_compounder_strat_pid);

            console.log(`User 1 withdraws ${ethers.utils.formatEther(UsersSharesBeforeFirstWithdrawal.div(2))} LP tokens from the maximizer vault`)

            await vaultHealer.connect(user1)["withdraw(uint256,uint256)"](maximizer_strat_pid, UsersSharesBeforeFirstWithdrawal.div(2));  
            
            const LPtokenBalanceAfterFirstWithdrawal = await LPtoken.balanceOf(user1.address);

            vaultSharesTotalAfterFirstWithdrawal = await strategyMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() 

            console.log(`We now have ${ethers.utils.formatEther(vaultSharesTotalAfterFirstWithdrawal)} total LP tokens left in the maximizer vault`)

            expect(LPtokenBalanceAfterFirstWithdrawal.sub(LPtokenBalanceBeforeFirstWithdrawal))
            .to.equal(
                (vaultSharesTotalInMaximizerBeforeWithdraw.sub(vaultSharesTotalAfterFirstWithdrawal))
                .sub(withdrawFee
                .mul(vaultSharesTotalInMaximizerBeforeWithdraw.sub(vaultSharesTotalAfterFirstWithdrawal))
                .div(10000))
                )
                ;
        })

/*        it('Should increase the user\'s rawBalance of CRYSTL shares when withdrawing from maximizer, while not touching the balance of crystl or crystl shares', async () => {
            user1CrystlBalanceAfterWithdraw = await TARGET_WANT.balanceOf(user1.address);
			user1CrystlShareBalanceAfterWithdraw = await vaultHealer.balanceOf(user1.address, crystl_compounder_strat_pid);
			user1CrystlShareRawBalanceAfterWithdraw = await vaultHealer.rawBalanceOf(user1.address, crystl_compounder_strat_pid);
            //console.log(`The user got ${ethers.utils.formatEther((user1CrystlBalanceAfterWithdraw).sub(user1CrystlBalanceBeforeWithdraw))} CRYSTL tokens back from the maximizer vault`)

            expect(user1CrystlBalanceAfterWithdraw).to.be.eq(user1CrystlBalanceBeforeWithdraw);
			expect(user1CrystlShareBalanceAfterWithdraw).to.be.eq(user1CrystlShareBalanceBeforeWithdraw);
			expect(user1CrystlShareRawBalanceAfterWithdraw).to.be.gt(user1CrystlShareRawBalanceBeforeWithdraw);
        })
*/

        // withdraw should also cause crystl to be returned to the user (all of it)
        it('Should return maxiTarget harvest to user 1 when they withdraw (above test)', async () => {
            user1CrystlBalanceAfterWithdraw = await TARGET_WANT.balanceOf(user1.address);
            console.log(`The user got ${ethers.utils.formatEther((user1CrystlBalanceAfterWithdraw).sub(user1CrystlBalanceBeforeWithdraw))} CRYSTL tokens back from the maximizer vault`)

            expect(user1CrystlBalanceAfterWithdraw).to.be.gt(user1CrystlBalanceBeforeWithdraw);
        })

        // Stake a round number of LPs (e.g., 1 or 0.0001) - not a round number yet!
        it('Should deposit 1500 of user2\'s LP tokens into the vault, increasing vaultSharesTotal by the correct amount', async () => {
            // const LPtokenBalanceOfUser2BeforeFirstDeposit = await LPtoken.balanceOf(user2.address);
            user2InitialDeposit = await LPtoken.balanceOf(user2.address); //ethers.utils.parseEther("15");
            const vaultSharesTotalBeforeUser2FirstDeposit = await strategyMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            console.log(`VaultSharesTotal is ${ethers.utils.formatEther(vaultSharesTotalBeforeUser2FirstDeposit)} LP tokens before user 2 deposits`)

            await LPtoken.connect(user2).approve(vaultHealer.address, user2InitialDeposit); //no, I have to approve the vaulthealer surely?
            await vaultHealer.connect(user2)["deposit(uint256,uint256)"](maximizer_strat_pid, user2InitialDeposit);
            const vaultSharesTotalAfterUser2FirstDeposit = await strategyMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            console.log(`User 2 deposits ${ethers.utils.formatEther(user2InitialDeposit)} LP tokens`)
            console.log(`VaultSharesTotal is ${ethers.utils.formatEther(vaultSharesTotalAfterUser2FirstDeposit)} LP tokens after user 2 deposits`)

            expect(user2InitialDeposit).to.equal(vaultSharesTotalAfterUser2FirstDeposit.sub(vaultSharesTotalBeforeUser2FirstDeposit)); //will this work for 2nd deposit? on normal masterchef?
        })

        it('Should mint ERC1155 tokens for user 2, with the maximizer_strat_pid of the strategy and equal to LP tokens deposited', async () => {
            userBalanceOfStrategyTokens = await vaultHealer.balanceOf(user2.address, maximizer_strat_pid);
            console.log(`User2 balance of ERC1155 tokens is now ${ethers.utils.formatEther(userBalanceOfStrategyTokens)} tokens`)
            expect(userBalanceOfStrategyTokens).to.eq(user2InitialDeposit); 
        })

        // Compound LPs (Call the earnSome function with this specific farm’s maximizer_strat_pid).
        // Check balance to ensure it increased as expected
        it('Should wait 10 blocks, then compound the maximizer vault by calling earnSome(), resulting in an increase in crystl in the crystl compounder', async () => {
            const vaultSharesTotalBeforeCallingEarnSome = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            console.log(`We start with ${ethers.utils.formatEther(vaultSharesTotalBeforeCallingEarnSome)} crystl tokens in the crystl compounder`)
            console.log(`We let 100 blocks pass, and then call earn...`)

            balanceMaticAtFeeAddressBeforeEarn = await ethers.provider.getBalance(FEE_ADDRESS); //note: MATIC, not WMATIC

            // console.log(`Block number before calling earn ${await ethers.provider.getBlockNumber()}`)
            // console.log(`vaultSharesTotalBeforeCallingEarnSome: ${vaultSharesTotalBeforeCallingEarnSome}`)

            for (i=0; i<5000;i++) { //minBlocksBetweenSwaps - can use this variable as an alternate to hardcoding a value
                await ethers.provider.send("evm_mine"); //creates a delay of 100 blocks - could adjust this to be minBlocksBetweenSwaps+1 blocks
            }

            await vaultHealer["earn(uint256[])"]([maximizer_strat_pid]);
            // console.log(`Block number after calling earn ${await ethers.provider.getBlockNumber()}`)

            vaultSharesTotalAfterCallingEarnSome = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            console.log(`After the earn call we have ${ethers.utils.formatEther(vaultSharesTotalAfterCallingEarnSome)} crystl tokens in the crystl compounder`)

            expect(vaultSharesTotalAfterCallingEarnSome).to.be.gt(vaultSharesTotalBeforeCallingEarnSome); //.toNumber()
        }) 

        it('Should pay 5% of earnedAmt to the feeAddress with each earn, in MATIC', async () => {
            balanceMaticAtFeeAddressAfterEarn = await ethers.provider.getBalance(FEE_ADDRESS); //note: MATIC, not WMATIC
            console.log(`MATIC at Fee Address went up by ${ethers.utils.formatEther(balanceMaticAtFeeAddressAfterEarn.sub(balanceMaticAtFeeAddressBeforeEarn))} tokens`)
            expect(balanceMaticAtFeeAddressAfterEarn).to.be.gt(balanceMaticAtFeeAddressBeforeEarn);
        })

        // Compound LPs (Call the earnSome function with this specific farm’s maximizer_strat_pid).
        // Check balance to ensure it increased as expected
        it('Should wait 10 blocks, then compound the CRYSTL Compounder by calling earnSome(), so that vaultSharesTotal is greater after than before', async () => {
            const vaultSharesTotalBeforeCallingEarnSome = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            const wantLockedTotalBeforeCallingEarnSome = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).wantLockedTotal()

            console.log(`Before calling earn on the CRYSTL compounder, we have ${ethers.utils.formatEther(vaultSharesTotalBeforeCallingEarnSome)} CRYSTL tokens in it`)
            console.log(`We let 100 blocks pass...`)
            // console.log(`Block number before calling earn ${await ethers.provider.getBlockNumber()}`)
            // console.log(`vaultSharesTotalBeforeCallingEarnSome: ${vaultSharesTotalBeforeCallingEarnSome}`)

            for (i=0; i<5000;i++) { //minBlocksBetweenSwaps - can use this variable as an alternate to hardcoding a value
                await ethers.provider.send("evm_mine"); //creates a delay of 100 blocks - could adjust this to be minBlocksBetweenSwaps+1 blocks
            }

            await vaultHealer["earn(uint256[])"]([crystl_compounder_strat_pid]);
            // console.log(`Block number after calling earn ${await ethers.provider.getBlockNumber()}`)

            vaultSharesTotalInCrystalCompounderAfterCallingEarnSome = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            // console.log(`vaultSharesTotalInCrystalCompounderAfterCallingEarnSome: ${vaultSharesTotalInCrystalCompounderAfterCallingEarnSome}`)
            console.log(`After calling earn on the CRYSTL compounder, we have ${ethers.utils.formatEther(vaultSharesTotalInCrystalCompounderAfterCallingEarnSome)} CRYSTL tokens in it`)
            const wantLockedTotalAfterCallingEarnSome = await strategyCrystlCompounder.wantLockedTotal() //.connect(vaultHealerOwnerSigner)

            expect(vaultSharesTotalInCrystalCompounderAfterCallingEarnSome).to.be.gt(vaultSharesTotalBeforeCallingEarnSome); //.toNumber()
        }) 
        
        // Unstake 50% of LPs. 
        // Check transaction to ensure withdraw fee amount is as expected and amount withdrawn in as expected
        it('Should withdraw 50% of user 2 LPs with correct withdraw fee amount (0.1%) and decrease users stakedWantTokens balance correctly', async () => {
            const LPtokenBalanceBeforeFirstWithdrawal = await LPtoken.balanceOf(user2.address);
            const UsersStakedTokensBeforeFirstWithdrawal = await vaultHealer.balanceOf(user2.address, maximizer_strat_pid);

            vaultSharesTotalInMaximizerBeforeWithdraw = await strategyMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal()

            user2CrystlBalanceBeforeWithdraw = await TARGET_WANT.balanceOf(user2.address);
            console.log(`User 2 withdraws ${ethers.utils.formatEther(UsersStakedTokensBeforeFirstWithdrawal.div(2))} LP tokens from the maximizer vault`)

            await vaultHealer.connect(user2)["withdraw(uint256,uint256)"](maximizer_strat_pid, UsersStakedTokensBeforeFirstWithdrawal.div(2)); 
            
            const LPtokenBalanceAfterFirstWithdrawal = await LPtoken.balanceOf(user2.address);

            vaultSharesTotalAfterFirstWithdrawal = await strategyMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() 
            console.log(`We now have ${ethers.utils.formatEther(vaultSharesTotalAfterFirstWithdrawal)} total LP tokens left in the maximizer vault`)

            expect(LPtokenBalanceAfterFirstWithdrawal.sub(LPtokenBalanceBeforeFirstWithdrawal))
            .to.equal(
                (vaultSharesTotalInMaximizerBeforeWithdraw.sub(vaultSharesTotalAfterFirstWithdrawal))
                .sub(withdrawFee
                .mul(vaultSharesTotalInMaximizerBeforeWithdraw.sub(vaultSharesTotalAfterFirstWithdrawal))
                .div(10000))
                )
                ;
        })

        // withdraw should also cause crystl to be returned to the user (all of it)
        it('Should return CRYSTL harvest to user 2 when they withdraw (above test)', async () => {
            user2CrystlBalanceAfterWithdraw = await TARGET_WANT.balanceOf(user2.address);

            console.log(`The user got ${ethers.utils.formatEther((user2CrystlBalanceAfterWithdraw).sub(user2CrystlBalanceBeforeWithdraw))} CRYSTL tokens back from the maximizer vault`)

            expect(user2CrystlBalanceAfterWithdraw).to.be.gt(user2CrystlBalanceBeforeWithdraw);
        })

               // Unstake 50% of LPs. 
        // Check transaction to ensure withdraw fee amount is as expected and amount withdrawn in as expected
        it('Should withdraw the other 50% of user 2 LPs with correct withdraw fee amount (0.1%) and decrease users stakedWantTokens balance correctly', async () => {
            const LPtokenBalanceBeforeSecondWithdrawal = await LPtoken.balanceOf(user2.address);
            const UsersStakedTokensBeforeSecondWithdrawal = await vaultHealer.balanceOf(user2.address, maximizer_strat_pid);

            vaultSharesTotalInMaximizerBeforeWithdraw = await strategyMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal()
          
            user2CrystlBalanceBeforeWithdraw = await TARGET_WANT.balanceOf(user2.address);
            console.log(`User 2 withdraws ${ethers.utils.formatEther(UsersStakedTokensBeforeSecondWithdrawal)} LP tokens from the maximizer vault`)

            await vaultHealer.connect(user2)["withdraw(uint256,uint256)"](maximizer_strat_pid, UsersStakedTokensBeforeSecondWithdrawal); 
            
            const LPtokenBalanceAfterSecondWithdrawal = await LPtoken.balanceOf(user2.address);

            vaultSharesTotalAfterSecondWithdrawal = await strategyMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() 

            console.log(`We now have ${ethers.utils.formatEther(vaultSharesTotalAfterSecondWithdrawal)} total LP tokens left in the maximizer vault`)

            expect(LPtokenBalanceAfterSecondWithdrawal.sub(LPtokenBalanceBeforeSecondWithdrawal))
            .to.equal(
                (vaultSharesTotalInMaximizerBeforeWithdraw.sub(vaultSharesTotalAfterSecondWithdrawal))
                .sub(withdrawFee
                .mul(vaultSharesTotalInMaximizerBeforeWithdraw.sub(vaultSharesTotalAfterSecondWithdrawal))
                .div(10000))
                )
                ;
        })

        // withdraw should also cause crystl to be returned to the user (all of it)
        it('Should return CRYSTL harvest to user 2 when they withdraw (above test)', async () => {
            user2CrystlBalanceAfterWithdraw = await TARGET_WANT.balanceOf(user2.address);

            console.log(`The user got ${ethers.utils.formatEther((user2CrystlBalanceAfterWithdraw).sub(user2CrystlBalanceBeforeWithdraw))} CRYSTL tokens back from the maximizer vault`)

            expect(user2CrystlBalanceAfterWithdraw).to.be.gt(user2CrystlBalanceBeforeWithdraw);
        })

        it('Should deposit 1500 LP tokens from user into the vault, increasing vaultSharesTotal by the correct amount', async () => {
            // const LPtokenBalanceOfUser2BeforeFirstDeposit = await LPtoken.balanceOf(user3.address);
			
			await vaultHealer["earn(uint256[])"]([crystl_compounder_strat_pid]); //call earn so there's not a large amount added from compounding
			
            user3InitialDeposit = await LPtoken.balanceOf(user3.address); //ethers.utils.parseEther("15");
            const vaultSharesTotalBeforeUser3FirstDeposit = await strategyMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            console.log(`VaultSharesTotal is ${ethers.utils.formatEther(vaultSharesTotalBeforeUser3FirstDeposit)} LP tokens before user 3 deposits`)

            await LPtoken.connect(user3).approve(vaultHealer.address, user3InitialDeposit); //no, I have to approve the vaulthealer surely?
            await vaultHealer.connect(user3)["deposit(uint256,uint256)"](maximizer_strat_pid, user3InitialDeposit);
            const user3vaultSharesTotalAfterUser3FirstDeposit = await strategyMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            console.log(`User 3 deposits ${ethers.utils.formatEther(user3InitialDeposit)} LP tokens`);
            console.log(`VaultSharesTotal is ${ethers.utils.formatEther(user3vaultSharesTotalAfterUser3FirstDeposit)} LP tokens after user 3 deposits`)

            expect(user3InitialDeposit).to.equal(user3vaultSharesTotalAfterUser3FirstDeposit.sub(vaultSharesTotalBeforeUser3FirstDeposit)); //will this work for 2nd deposit? on normal masterchef?
        })

        it('Should mint ERC1155 tokens for this user, with the maximizer_strat_pid of the strategy and equal to LP tokens deposited', async () => {
            userBalanceOfStrategyTokens = await vaultHealer.balanceOf(user3.address, maximizer_strat_pid);
            console.log(`User3 balance of ERC1155 tokens is now ${ethers.utils.formatEther(userBalanceOfStrategyTokens)} tokens`)
            expect(userBalanceOfStrategyTokens).to.eq(user3InitialDeposit); 
        })

        it('Should deposit 1500 TARGET_WANT tokens from user 4 directly into the crystl compounder vault, increasing vaultSharesTotal by the correct amount', async () => {
            user4InitialDeposit = await TARGET_WANT.balanceOf(user4.address); //ethers.utils.parseEther("1500");
            user4InitialCrystlBalance = await TARGET_WANT.balanceOf(user4.address);
            user4InitialCrystlShares = await vaultHealer.balanceOf(user4.address, crystl_compounder_strat_pid);
            totalCrystlVaultSharesBefore = await vaultHealer.totalSupply(crystl_compounder_strat_pid);

            console.log("user4InitialCrystlBalance: ", ethers.utils.formatEther(user4InitialCrystlBalance));
            await TARGET_WANT.connect(user4).approve(vaultHealer.address, user4InitialDeposit); 

            await vaultHealer["earn(uint256[])"]([maximizer_strat_pid,crystl_compounder_strat_pid]);

            const vaultSharesTotalBeforeUser4FirstDeposit = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            const wantLockedTotalBeforeUser4FirstDeposit = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).wantLockedTotal() //=0
            console.log(`VaultSharesTotal is ${ethers.utils.formatEther(vaultSharesTotalBeforeUser4FirstDeposit)} TARGET_WANT tokens before user 4 deposits`)
            console.log(`WantLockedTotal is ${ethers.utils.formatEther(wantLockedTotalBeforeUser4FirstDeposit)} TARGET_WANT tokens before user 4 deposits`)
            
            totalCrystlVaultSharesBefore = await vaultHealer.totalSupply(crystl_compounder_strat_pid);

            await vaultHealer.connect(user4)["deposit(uint256,uint256)"](crystl_compounder_strat_pid, user4InitialDeposit);
            const vaultSharesTotalAfterUser4FirstDeposit = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            const wantLockedTotalAfterUser4FirstDeposit = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).wantLockedTotal() //=0

            console.log(`User 4 deposits ${ethers.utils.formatEther(user4InitialDeposit)} TARGET_WANT tokens`);
            console.log(`VaultSharesTotal is ${ethers.utils.formatEther(vaultSharesTotalAfterUser4FirstDeposit)} TARGET_WANT tokens after user 4 deposits`)
            console.log(`WantLockedTotal is ${ethers.utils.formatEther(wantLockedTotalAfterUser4FirstDeposit)} TARGET_WANT tokens before user 4 deposits`)
            
            user4FinalCrystlBalance = await TARGET_WANT.balanceOf(user4.address);
            user4FinalCrystlShares = await vaultHealer.balanceOf(user4.address, crystl_compounder_strat_pid)
            totalCrystlVaultSharesAfter = await vaultHealer.totalSupply(crystl_compounder_strat_pid);

            expect(user4FinalCrystlShares.sub(user4InitialCrystlShares)).to.equal((totalCrystlVaultSharesAfter.sub(totalCrystlVaultSharesBefore)))
			console.log("user4InitialCrystlBalance", ethers.utils.formatEther(user4InitialCrystlBalance))
			console.log("user4FinalCrystlBalance", ethers.utils.formatEther(user4FinalCrystlBalance))
			console.log("wantLockedTotalBeforeUser4FirstDeposit", ethers.utils.formatEther(wantLockedTotalBeforeUser4FirstDeposit))
			console.log("wantLockedTotalAfterUser4FirstDeposit", ethers.utils.formatEther(wantLockedTotalAfterUser4FirstDeposit))
            expect(user4InitialCrystlBalance.sub(user4FinalCrystlBalance)).to.be.closeTo(wantLockedTotalAfterUser4FirstDeposit.sub(wantLockedTotalBeforeUser4FirstDeposit), 10000000000000);
        })

        // Compound LPs (Call the earnSome function with this specific farm’s maximizer_strat_pid).
        // Check balance to ensure it increased as expected
        it('Should wait 10 blocks, then compound the maximizer vault by calling earnSome(), resulting in an increase in crystl in the crystl compounder', async () => {
            const vaultSharesTotalBeforeCallingEarnSome = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            console.log(`We start with ${ethers.utils.formatEther(vaultSharesTotalBeforeCallingEarnSome)} crystl tokens in the crystl compounder`)
            console.log(`We let 100 blocks pass, and then call earn...`)

            balanceMaticAtFeeAddressBeforeEarn = await ethers.provider.getBalance(FEE_ADDRESS); //note: MATIC, not WMATIC

            // console.log(`Block number before calling earn ${await ethers.provider.getBlockNumber()}`)
            // console.log(`vaultSharesTotalBeforeCallingEarnSome: ${vaultSharesTotalBeforeCallingEarnSome}`)

            for (i=0; i<5000;i++) { //minBlocksBetweenSwaps - can use this variable as an alternate to hardcoding a value
                await ethers.provider.send("evm_mine"); //creates a delay of 100 blocks - could adjust this to be minBlocksBetweenSwaps+1 blocks
            }

            await vaultHealer["earn(uint256[])"]([maximizer_strat_pid]);
            // console.log(`Block number after calling earn ${await ethers.provider.getBlockNumber()}`)

            vaultSharesTotalAfterCallingEarnSome = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            console.log(`After the earn call we have ${ethers.utils.formatEther(vaultSharesTotalAfterCallingEarnSome)} crystl tokens in the crystl compounder`)

            expect(vaultSharesTotalAfterCallingEarnSome).to.be.gt(vaultSharesTotalBeforeCallingEarnSome); //.toNumber()
        }) 

        it('Should pay 5% of earnedAmt to the feeAddress with each earn, in MATIC', async () => {
            balanceMaticAtFeeAddressAfterEarn = await ethers.provider.getBalance(FEE_ADDRESS); //note: MATIC, not WMATIC
            console.log(`MATIC at Fee Address went up by ${ethers.utils.formatEther(balanceMaticAtFeeAddressAfterEarn.sub(balanceMaticAtFeeAddressBeforeEarn))} tokens`)
            expect(balanceMaticAtFeeAddressAfterEarn).to.be.gt(balanceMaticAtFeeAddressBeforeEarn);
        })

        // Compound LPs (Call the earnSome function with this specific farm’s maximizer_strat_pid).
        // Check balance to ensure it increased as expected
        it('Should wait 10 blocks, then compound the TARGET_WANT Compounder by calling earnSome(), so that vaultSharesTotal is greater after than before', async () => {
            const vaultSharesTotalBeforeCallingEarnSome = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            const wantLockedTotalBeforeCallingEarnSome = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).wantLockedTotal()

            console.log(`Before calling earn on the TARGET_WANT compounder, we have ${ethers.utils.formatEther(vaultSharesTotalBeforeCallingEarnSome)} TARGET_WANT tokens in it`)
            console.log(`We let 100 blocks pass...`)
            // console.log(`Block number before calling earn ${await ethers.provider.getBlockNumber()}`)
            // console.log(`vaultSharesTotalBeforeCallingEarnSome: ${vaultSharesTotalBeforeCallingEarnSome}`)

            for (i=0; i<5000;i++) { //minBlocksBetweenSwaps - can use this variable as an alternate to hardcoding a value
                await ethers.provider.send("evm_mine"); //creates a delay of 100 blocks - could adjust this to be minBlocksBetweenSwaps+1 blocks
            }

            await vaultHealer["earn(uint256[])"]([crystl_compounder_strat_pid]);
            // console.log(`Block number after calling earn ${await ethers.provider.getBlockNumber()}`)

            vaultSharesTotalInCrystalCompounderAfterCallingEarnSome = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            // console.log(`vaultSharesTotalInCrystalCompounderAfterCallingEarnSome: ${vaultSharesTotalInCrystalCompounderAfterCallingEarnSome}`)
            console.log(`After calling earn on the TARGET_WANT compounder, we have ${ethers.utils.formatEther(vaultSharesTotalInCrystalCompounderAfterCallingEarnSome)} TARGET_WANT tokens in it`)
            const wantLockedTotalAfterCallingEarnSome = await strategyCrystlCompounder.wantLockedTotal() //.connect(vaultHealerOwnerSigner)

            expect(vaultSharesTotalInCrystalCompounderAfterCallingEarnSome).to.be.gt(vaultSharesTotalBeforeCallingEarnSome); //.toNumber()
        }) 
        
        // Unstake 50% of LPs. 
        // Check transaction to ensure withdraw fee amount is as expected and amount withdrawn in as expected
        it('Should withdraw 50% of user 3 LPs with correct withdraw fee amount (0.1%) and decrease users stakedWantTokens balance correctly', async () => {
            const LPtokenBalanceBeforeFirstWithdrawal = await LPtoken.balanceOf(user3.address);
            const UsersStakedTokensBeforeFirstWithdrawal = await vaultHealer.balanceOf(user3.address, maximizer_strat_pid);

            vaultSharesTotalInMaximizerBeforeWithdraw = await strategyMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            user3CrystlBalanceBeforeWithdraw = await TARGET_WANT.balanceOf(user3.address);
            console.log(`User 3 withdraws ${ethers.utils.formatEther(UsersStakedTokensBeforeFirstWithdrawal.div(2))} LP tokens from the maximizer vault`)

            await vaultHealer.connect(user3)["withdraw(uint256,uint256)"](maximizer_strat_pid, UsersStakedTokensBeforeFirstWithdrawal.div(2));  
            
            const LPtokenBalanceAfterFirstWithdrawal = await LPtoken.balanceOf(user3.address);

            vaultSharesTotalAfterFirstWithdrawal = await strategyMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() 

            console.log(`We now have ${ethers.utils.formatEther(vaultSharesTotalAfterFirstWithdrawal)} total LP tokens left in the maximizer vault`)

            expect(LPtokenBalanceAfterFirstWithdrawal.sub(LPtokenBalanceBeforeFirstWithdrawal))
            .to.equal(
                (vaultSharesTotalInMaximizerBeforeWithdraw.sub(vaultSharesTotalAfterFirstWithdrawal))
                .sub(withdrawFee
                .mul(vaultSharesTotalInMaximizerBeforeWithdraw.sub(vaultSharesTotalAfterFirstWithdrawal))
                .div(10000))
                )
                ;
        })

        // withdraw should also cause crystl to be returned to the user (all of it)
        it('Should return TARGET_WANT harvest to user when they withdraw (above test)', async () => {
            user3CrystlBalanceAfterWithdraw = await TARGET_WANT.balanceOf(user3.address);
            console.log(`The user got ${ethers.utils.formatEther((user3CrystlBalanceAfterWithdraw).sub(user3CrystlBalanceBeforeWithdraw))} TARGET_WANT tokens back from the maximizer vault`)
            expect(user3CrystlBalanceAfterWithdraw).to.be.gt(user3CrystlBalanceBeforeWithdraw);
        })

        it('Should transfer 1155 tokens from user 1 to user 3, updating shares accurately', async () => {
            const User3StakedTokensBeforeTransfer = await vaultHealer.balanceOf(user3.address, maximizer_strat_pid);
            const User1StakedTokensBeforeTransfer = await vaultHealer.balanceOf(user1.address, maximizer_strat_pid);

			user1CrystlShareBalanceBeforeTransfer = await vaultHealer.balanceOf(user1.address, crystl_compounder_strat_pid);
			user3CrystlShareBalanceBeforeTransfer = await vaultHealer.balanceOf(user3.address, crystl_compounder_strat_pid);

            User3OffsetBeforeTransfer = await vaultHealer.maximizerEarningsOffset(user3.address,maximizer_strat_pid);
            
            vaultHealer.connect(user1).setApprovalForAll(user3.address, true);

            await vaultHealer.connect(user3).safeTransferFrom(
                user1.address,
                user3.address,
                maximizer_strat_pid,
                User1StakedTokensBeforeTransfer,
                0);

            const User3StakedTokensAfterTransfer = await vaultHealer.balanceOf(user3.address, maximizer_strat_pid);
            const User1StakedTokensAfterTransfer = await vaultHealer.balanceOf(user1.address, maximizer_strat_pid);

            expect(User3StakedTokensBeforeTransfer.sub(User3StakedTokensAfterTransfer)).to.eq(User1StakedTokensAfterTransfer.sub(User1StakedTokensBeforeTransfer))
        })

        it('Transfer should not affect crystl share balances', async () => {
			user1CrystlShareBalanceAfterTransfer = await vaultHealer.balanceOf(user1.address, crystl_compounder_strat_pid);
			user3CrystlShareBalanceAfterTransfer = await vaultHealer.balanceOf(user3.address, crystl_compounder_strat_pid);

			expect(user1CrystlShareBalanceAfterTransfer).to.be.eq(user1CrystlShareBalanceBeforeTransfer);
			expect(user3CrystlShareBalanceAfterTransfer).to.be.eq(user3CrystlShareBalanceBeforeTransfer);
        })		

        it('Should increase offset when you receive transferred tokens', async () => {
             // const User1OffsetAfterTransfer = await vaultHealer.rewardDebt(maximizer_strat_pid, user1.address);
			const User3OffsetAfterTransfer = await vaultHealer.maximizerEarningsOffset(user3.address,maximizer_strat_pid);

             expect(User3OffsetAfterTransfer).to.be.gt(User3OffsetBeforeTransfer);
        })
/*
        // withdraw should also cause crystl to be returned to the user (all of it)
        it('Should return TARGET_WANT harvest to user when they withdraw (above test)', async () => {
            user3CrystlBalanceAfterWithdraw = await TARGET_WANT.balanceOf(user3.address);

            console.log(`The user got ${ethers.utils.formatEther((user3CrystlBalanceAfterWithdraw).sub(user3CrystlBalanceBeforeWithdraw))} TARGET_WANT tokens back from the maximizer vault`)

            expect(user3CrystlBalanceAfterWithdraw).to.be.gt(user3CrystlBalanceBeforeWithdraw);
        })
*/
        // Deposit 100% of users LP tokens into vault, ensure balance increases as expected.
        it('Should accurately increase vaultSharesTotal upon second deposit of 200 LP tokens by user1', async () => {
            user1SecondDepositAmount = await LPtoken.balanceOf(user1.address); //ethers.utils.parseEther("2");
            await LPtoken.approve(vaultHealer.address, user1SecondDepositAmount);

            const vaultSharesTotalBeforeSecondDeposit = await strategyMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            console.log(`VaultSharesTotal is ${ethers.utils.formatEther(vaultSharesTotalBeforeSecondDeposit)} LP tokens before user 1 makes their 2nd deposit`)

            await vaultHealer["deposit(uint256,uint256)"](maximizer_strat_pid, user1SecondDepositAmount); //user1 (default signer) deposits LP tokens into specified maximizer_strat_pid vaulthealer
            console.log(`User 1 deposits ${ethers.utils.formatEther(user1SecondDepositAmount)} LP tokens`);

            const vaultSharesTotalAfterSecondDeposit = await strategyMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0;
            console.log(`VaultSharesTotal is ${ethers.utils.formatEther(vaultSharesTotalAfterSecondDeposit)} LP tokens after user 1 makes their 2nd deposit`)

            expect(user1SecondDepositAmount).to.equal(vaultSharesTotalAfterSecondDeposit.sub(vaultSharesTotalBeforeSecondDeposit)); //will this work for 2nd deposit? on normal masterchef?
        })
        

        // Withdraw 100%
        it('Should withdraw remaining user1 balance back to user1, minus withdrawal fee (0.1%)', async () => {
            userBalanceOfStrategyTokensBeforeStaking = await vaultHealer.balanceOf(user1.address, maximizer_strat_pid);
            console.log(`User1 now has ${ethers.utils.formatEther(userBalanceOfStrategyTokensBeforeStaking)} tokens in the maximizer vault`)

            const LPtokenBalanceBeforeFinalWithdrawal = await LPtoken.balanceOf(user1.address)

            const UsersStakedTokensBeforeFinalWithdrawal = await vaultHealer.balanceOf(user1.address, maximizer_strat_pid);

            user1CrystlShareBalanceBeforeFinalWithdraw = await vaultHealer.balanceOf(user1.address, crystl_compounder_strat_pid);
            user1CrystlBalanceBeforeWithdraw = await TARGET_WANT.balanceOf(user1.address);
			console.log("bal_before:", user1CrystlBalanceBeforeWithdraw);
            await vaultHealer["withdraw(uint256,uint256)"](maximizer_strat_pid,ethers.constants.MaxUint256); //user1 (default signer) deposits 1 of LP tokens into maximizer_strat_pid 0 of vaulthealer
            
            const LPtokenBalanceAfterFinalWithdrawal = await LPtoken.balanceOf(user1.address);

            UsersStakedTokensAfterFinalWithdrawal = await vaultHealer.balanceOf(user1.address, maximizer_strat_pid);

            expect(LPtokenBalanceAfterFinalWithdrawal.sub(LPtokenBalanceBeforeFinalWithdrawal))
            .to.equal(
                (UsersStakedTokensBeforeFinalWithdrawal.sub(UsersStakedTokensAfterFinalWithdrawal))
                .sub(
                    (withdrawFee)
                    .mul(UsersStakedTokensBeforeFinalWithdrawal.sub(UsersStakedTokensAfterFinalWithdrawal))
                    .div(10000)
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
            user1CrystlBalanceAfterWithdraw = await TARGET_WANT.balanceOf(user1.address);
			console.log("bal_after:", user1CrystlBalanceAfterWithdraw);
            console.log(`The user got ${ethers.utils.formatEther((user1CrystlBalanceAfterWithdraw).sub(user1CrystlBalanceBeforeWithdraw))} TARGET_WANT tokens back from the maximizer vault`)
            expect(user1CrystlBalanceAfterWithdraw).to.be.gt(user1CrystlBalanceBeforeWithdraw);
        })

         // Withdraw 100%
         it('Should withdraw remaining user3 balance back to user3, minus withdrawal fee (0.1%)', async () => {
            userBalanceOfStrategyTokensBeforeStaking = await vaultHealer.balanceOf(user3.address, maximizer_strat_pid);
            console.log(`User1 now has ${ethers.utils.formatEther(userBalanceOfStrategyTokensBeforeStaking)} tokens in the maximizer vault`)

            const LPtokenBalanceBeforeFinalWithdrawal = await LPtoken.balanceOf(user3.address)

            const UsersStakedTokensBeforeFinalWithdrawal = await vaultHealer.balanceOf(user3.address, maximizer_strat_pid);

            user1CrystlShareBalanceBeforeFinalWithdraw = await vaultHealer.balanceOf(user3.address, crystl_compounder_strat_pid);
            user1CrystlBalanceBeforeWithdraw = await TARGET_WANT.balanceOf(user3.address);

            await vaultHealer.connect(user3)["withdraw(uint256,uint256)"](maximizer_strat_pid,ethers.constants.MaxUint256); //user3 (default signer) deposits 1 of LP tokens into maximizer_strat_pid 0 of vaulthealer
            
            const LPtokenBalanceAfterFinalWithdrawal = await LPtoken.balanceOf(user3.address);

            UsersStakedTokensAfterFinalWithdrawal = await vaultHealer.balanceOf(user3.address, maximizer_strat_pid);

            expect(LPtokenBalanceAfterFinalWithdrawal.sub(LPtokenBalanceBeforeFinalWithdrawal))
            .to.equal(
                (UsersStakedTokensBeforeFinalWithdrawal.sub(UsersStakedTokensAfterFinalWithdrawal))
                .sub(
                    (withdrawFee)
                    .mul(UsersStakedTokensBeforeFinalWithdrawal.sub(UsersStakedTokensAfterFinalWithdrawal))
                    .div(10000)
                )
                );
        })

        it('Should withdraw all of user4s TARGET_WANT tokens directly from the crystl compounder vault, resulting in what?', async () => {
            user4InitialCrystlBalance = await TARGET_WANT.balanceOf(user4.address);
            user4InitialCrystlShares = await vaultHealer.balanceOf(user4.address, crystl_compounder_strat_pid);
            console.log("user4InitialCrystlBalance: ", user4InitialCrystlBalance);
            console.log("user4InitialCrystlShares: ", user4InitialCrystlShares);
            totalCrystlVaultSharesBefore = await vaultHealer.totalSupply(crystl_compounder_strat_pid);

            await vaultHealer["earn(uint256[])"]([maximizer_strat_pid,crystl_compounder_strat_pid]);
            const vaultSharesTotalBeforeUser4Withdrawal = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            const wantLockedTotalBeforeUser4Withdrawal = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).wantLockedTotal() //=0

            console.log(`VaultSharesTotal is ${ethers.utils.formatEther(vaultSharesTotalBeforeUser4Withdrawal)} TARGET_WANT tokens before user 4 withdraws`)
            await vaultHealer.connect(user4)["withdraw(uint256,uint256)"](crystl_compounder_strat_pid,ethers.constants.MaxUint256);

            const vaultSharesTotalAfterUser4Withdrawal = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            const wantLockedTotalAfterUser4Withdrawal = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).wantLockedTotal() //=0

            console.log(`VaultSharesTotal is ${ethers.utils.formatEther(vaultSharesTotalAfterUser4Withdrawal)} TARGET_WANT tokens after user 4 withdraws`)
            user4FinalCrystlBalance = await TARGET_WANT.balanceOf(user4.address);
            user4FinalCrystlShares = await vaultHealer.balanceOf(user4.address, crystl_compounder_strat_pid);
            totalCrystlVaultSharesAfter = await vaultHealer.totalSupply(crystl_compounder_strat_pid);

            expect(user4InitialCrystlShares.sub(user4FinalCrystlShares)).to.equal(
                (totalCrystlVaultSharesBefore.sub(totalCrystlVaultSharesAfter)))
            
            expect(user4FinalCrystlBalance.sub(user4InitialCrystlBalance)).to.be.closeTo(wantLockedTotalBeforeUser4Withdrawal.sub(wantLockedTotalAfterUser4Withdrawal)
                .sub(withdrawFee
                .mul(wantLockedTotalBeforeUser4Withdrawal.sub(wantLockedTotalAfterUser4Withdrawal))
                .div(10000)),
                "10000000000000000"
                )
        })

        it('Should leave zero crystl in the crystl compounder once all 3 users have fully withdrawn their funds', async () => {
            vaultSharesTotalInCrystlCompounderAtEnd = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            vaultSharesTotalInMaximizerAtEnd = await strategyMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal()

            console.log(`There are now ${ethers.utils.formatEther(vaultSharesTotalInMaximizerAtEnd)} LP tokens in the maximizer and 
            ${ethers.utils.formatEther(vaultSharesTotalInCrystlCompounderAtEnd)} crystl tokens left in the compounder`);
            expect(vaultSharesTotalInCrystlCompounderAtEnd).to.eq(0);
        })
    })
})

