// import hre from "hardhat";

const { tokens, accounts, routers } = require('../configs/addresses.js');
const { WMATIC, CRYSTL, DAI } = tokens.polygon;
const { FEE_ADDRESS, BURN_ADDRESS, ZERO_ADDRESS } = accounts.polygon;
const { expect } = require('chai');
const { ethers } = require('hardhat');
const { IUniRouter02_abi } = require('./abi_files/IUniRouter02_abi.js');
const { token_abi } = require('./abi_files/token_abi.js');
const { IWETH_abi } = require('./abi_files/IWETH_abi.js');
const { IUniswapV2Pair_abi } = require('./abi_files/IUniswapV2Pair_abi.js');
const { boostPool_abi } = require('./abi_files/boostPool_abi.js');
const { getContractAddress } = require('@ethersproject/address')

//////////////////////////////////////////////////////////////////////////
// THESE FIVE VARIABLES BELOW NEED TO BE SET CORRECTLY FOR A GIVEN TEST //
//////////////////////////////////////////////////////////////////////////

const STRATEGY_CONTRACT_TYPE = 'Strategy'; //<-- change strategy type to the contract deployed for this strategy
const { dinoswapVaults } = require('../configs/dinoswapVaults'); //<-- replace all references to 'dinoswapVaults' (for example), with the right '...Vaults' name
const { crystlVault } = require('../configs/crystlVault'); //<-- replace all references to 'dinoswapVaults' (for example), with the right '...Vaults' name

const MASTERCHEF = dinoswapVaults[0].masterchef;
const VAULT_HEALER = dinoswapVaults[0].vaulthealer;
const WANT = dinoswapVaults[0].want;
const EARNED = dinoswapVaults[0].earned;
const PID = dinoswapVaults[0].PID;
const CRYSTL_ROUTER = routers.polygon.APESWAP_ROUTER;
const LP_AND_EARN_ROUTER = dinoswapVaults[0].router;

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
		
        // const from = user1.address;
        // const nonce = 1 + await user1.getTransactionCount();
		// vaultHealer = await getContractAddress({from, nonce});
		withdrawFee = ethers.BigNumber.from(10);
        earnFee = ethers.BigNumber.from(500);

		VaultChonk = await ethers.getContractFactory("VaultChonk");
		vaultChonk = await VaultChonk.deploy();
		VaultHealer = await ethers.getContractFactory("VaultHealer", {
			libraries: {
				VaultChonk: vaultChonk.address,
			},
		});
        vaultHealer = await VaultHealer.deploy();
		vaultFeeManager = await ethers.getContractAt("VaultFeeManager", await vaultHealer.vaultFeeManager());

		
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

		let [tacticsA, tacticsB] = await strategyImplementation.generateTactics(
			dinoswapVaults[0]['masterchef'],
            dinoswapVaults[0]['PID'],
            0, //have to look at contract and see
            ethers.BigNumber.from("0x93f1a40b23000000"), //vaultSharesTotal - includes selector and encoded call format
            ethers.BigNumber.from("0xe2bbb15824000000"), //deposit - includes selector and encoded call format
            ethers.BigNumber.from("0x441a3e7024000000"), //withdraw - includes selector and encoded call format
            ethers.BigNumber.from("0x441a3e702f000000"), //harvest - includes selector and encoded call format
            ethers.BigNumber.from("0x5312ea8e20000000") //includes selector and encoded call format
        );

        DEPLOYMENT_DATA = await strategyImplementation.generateConfig(
            tacticsA,
			tacticsB,
			dinoswapVaults[0]['want'],
			40,
			LP_AND_EARN_ROUTER,
			magnetite.address,
			240,
			false,
			dinoswapVaults[0]['earned'],
			[40]
		);

        LPtoken = await ethers.getContractAt(IUniswapV2Pair_abi, WANT);
        TOKEN0ADDRESS = await LPtoken.token0()
        TOKEN1ADDRESS = await LPtoken.token1()
        TOKEN_OTHER = CRYSTL;

        vaultHealerOwnerSigner = user1

		await vaultHealer.connect(vaultHealerOwnerSigner).createVault(strategyImplementation.address, DEPLOYMENT_DATA);
		strat1_pid = await vaultHealer.numVaultsBase();
		strat1 = await ethers.getContractAt('Strategy', await vaultHealer.strat(strat1_pid))
		
        //create the revshare pool
        RevSharePool = await ethers.getContractFactory("RevSharePool", {});
        //need the wantToken address from the strategy!
		
        revSharePool = await RevSharePool.deploy(await strat1.wantToken(), WMATIC, 86400, await ethers.provider.getBlockNumber());
		
		await vaultFeeManager.setDefaultWithdrawFee(FEE_ADDRESS, withdrawFee);
		await vaultFeeManager.setDefaultEarnFees([ revSharePool.address, ZERO_ADDRESS, ZERO_ADDRESS ], [earnFee, 0, 0]);		
		
        console.log("got here");

        crystlRouter = await ethers.getContractAt(IUniRouter02_abi, CRYSTL_ROUTER);

        await crystlRouter.swapExactETHForTokens(0, [WMATIC, CRYSTL], revSharePool.address, Date.now() + 900, { value: ethers.utils.parseEther("45") })

        await network.provider.send("hardhat_setBalance", [
            user1.address,
            "0x21E19E0C9BAB240000000", //amount of 1000 in hex
        ]);

        await network.provider.send("hardhat_setBalance", [
            user2.address,
            "0x21E19E0C9BAB240000000", //amount of 1000 in hex
        ]);

        await network.provider.send("hardhat_setBalance", [
            user3.address,
            "0x21E19E0C9BAB240000000", //amount of 1000 in hex
        ]);

        await network.provider.send("hardhat_setBalance", [
            user4.address,
            "0x21E19E0C9BAB240000000", //amount of 1000 in hex
        ]);
	
        LPandEarnRouter = await ethers.getContractAt(IUniRouter02_abi, LP_AND_EARN_ROUTER);

        if (TOKEN0ADDRESS == ethers.utils.getAddress(WMATIC) ){
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN0ADDRESS); 
            await wmatic_token.deposit({ value: ethers.utils.parseEther("4500") });
        } else {
            await LPandEarnRouter.swapExactETHForTokens(0, [WMATIC, TOKEN0ADDRESS], user1.address, Date.now() + 900, { value: ethers.utils.parseEther("4500") })
        }
        if (TOKEN1ADDRESS == ethers.utils.getAddress(WMATIC)) {
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN1ADDRESS); 
            await wmatic_token.deposit({ value: ethers.utils.parseEther("4500") });
        } else {
            await LPandEarnRouter.swapExactETHForTokens(0, [WMATIC, TOKEN1ADDRESS], user1.address, Date.now() + 900, { value: ethers.utils.parseEther("4500") })
        }

        if (TOKEN0ADDRESS == ethers.utils.getAddress(WMATIC) ){
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN0ADDRESS); 
            await wmatic_token.connect(user2).deposit({ value: ethers.utils.parseEther("4500") });
        } else {
            await LPandEarnRouter.connect(user2).swapExactETHForTokens(0, [WMATIC, TOKEN0ADDRESS], user2.address, Date.now() + 900, { value: ethers.utils.parseEther("4500") })
        }
        if (TOKEN1ADDRESS == ethers.utils.getAddress(WMATIC)) {
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN1ADDRESS); 
            await wmatic_token.connect(user2).deposit({ value: ethers.utils.parseEther("4500") });
        } else {
            await LPandEarnRouter.connect(user2).swapExactETHForTokens(0, [WMATIC, TOKEN1ADDRESS], user2.address, Date.now() + 900, { value: ethers.utils.parseEther("4500") })
        }

        if (TOKEN0ADDRESS == ethers.utils.getAddress(WMATIC) ){
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN0ADDRESS); 
            await wmatic_token.connect(user3).deposit({ value: ethers.utils.parseEther("4500") });
        } else {
            await LPandEarnRouter.connect(user3).swapExactETHForTokens(0, [WMATIC, TOKEN0ADDRESS], user3.address, Date.now() + 900, { value: ethers.utils.parseEther("4500") })
        }
        if (TOKEN1ADDRESS == ethers.utils.getAddress(WMATIC)) {
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN1ADDRESS); 
            await wmatic_token.connect(user3).deposit({ value: ethers.utils.parseEther("4500") });
        } else {
            await LPandEarnRouter.connect(user3).swapExactETHForTokens(0, [WMATIC, TOKEN1ADDRESS], user3.address, Date.now() + 900, { value: ethers.utils.parseEther("4500") })
        }

        if (TOKEN0ADDRESS == ethers.utils.getAddress(WMATIC) ){
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN0ADDRESS); 
            await wmatic_token.connect(user4).deposit({ value: ethers.utils.parseEther("3000") });
        } else {
            await LPandEarnRouter.connect(user4).swapExactETHForTokens(0, [WMATIC, TOKEN0ADDRESS], user4.address, Date.now() + 900, { value: ethers.utils.parseEther("3000") })
        }
        if (TOKEN1ADDRESS == ethers.utils.getAddress(WMATIC)) {
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN1ADDRESS); 
            await wmatic_token.connect(user4).deposit({ value: ethers.utils.parseEther("3000") });
        } else {
            await LPandEarnRouter.connect(user4).swapExactETHForTokens(0, [WMATIC, TOKEN1ADDRESS], user4.address, Date.now() + 900, { value: ethers.utils.parseEther("3000") })
        }
		

        await crystlRouter.connect(user4).swapExactETHForTokens(0, [WMATIC, TOKEN_OTHER], user4.address, Date.now() + 900, { value: ethers.utils.parseEther("3000") })


        //create instances of token0 and token1
        token0 = await ethers.getContractAt(token_abi, TOKEN0ADDRESS);
        token1 = await ethers.getContractAt(token_abi, TOKEN1ADDRESS);
        
        //user 1 adds liquidity to get LP tokens
        var token0BalanceUser1 = await token0.balanceOf(user1.address);
        await token0.approve(LPandEarnRouter.address, token0BalanceUser1);
		
        var token1BalanceUser1 = await token1.balanceOf(user1.address);
        await token1.approve(LPandEarnRouter.address, token1BalanceUser1);
		
        await LPandEarnRouter.addLiquidity(TOKEN0ADDRESS, TOKEN1ADDRESS, token0BalanceUser1, token1BalanceUser1, 0, 0, user1.address, Date.now() + 900)

        //user 2 adds liquidity to get LP tokens
        var token0BalanceUser2 = await token0.balanceOf(user2.address);
        await token0.connect(user2).approve(LPandEarnRouter.address, token0BalanceUser2);
        
        var token1BalanceUser2 = await token1.balanceOf(user2.address);
        await token1.connect(user2).approve(LPandEarnRouter.address, token1BalanceUser2);

        await LPandEarnRouter.connect(user2).addLiquidity(TOKEN0ADDRESS, TOKEN1ADDRESS, token0BalanceUser2, token1BalanceUser2, 0, 0, user2.address, Date.now() + 900)
        
        //user 3 adds liquidity to get LP tokens
        var token0BalanceUser3 = await token0.balanceOf(user3.address);
        await token0.connect(user3).approve(LPandEarnRouter.address, token0BalanceUser3);
        
        var token1BalanceUser3 = await token1.balanceOf(user3.address);
        await token1.connect(user3).approve(LPandEarnRouter.address, token1BalanceUser3);

        await LPandEarnRouter.connect(user3).addLiquidity(TOKEN0ADDRESS, TOKEN1ADDRESS, token0BalanceUser3, token1BalanceUser3, 0, 0, user3.address, Date.now() + 900)
        
        tokenOther = await ethers.getContractAt(token_abi, TOKEN_OTHER);

    });

    describe(`Testing depositing into vault, compounding vault, withdrawing from vault:
    `, () => {
        // Stake a round number of LPs (e.g., 1 or 0.0001) - not a round number yet!
        it('Should deposit user1\'s 100 LP tokens into the vault, increasing vaultSharesTotal by the correct amount', async () => {
            // initialLPtokenBalance = await LPtoken.balanceOf(user1.address);
            const user1InitialDeposit = (await LPtoken.balanceOf(user1.address)).div(2); //ethers.utils.parseEther("5000");

            await LPtoken.connect(user1).approve(vaultHealer.address, user1InitialDeposit);
            LPtokenBalanceBeforeFirstDeposit = await LPtoken.balanceOf(user1.address);
            await vaultHealer.connect(user1)["deposit(uint256,uint256,bytes)"](strat1_pid, user1InitialDeposit, []);
            const vaultSharesTotalAfterFirstDeposit = await strat1.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            console.log(`User1 deposits ${ethers.utils.formatEther(user1InitialDeposit)} LP tokens`)
            console.log(`Vault Shares Total went up by ${ethers.utils.formatEther(vaultSharesTotalAfterFirstDeposit)} LP tokens`)

            expect(user1InitialDeposit).to.equal(vaultSharesTotalAfterFirstDeposit);
        })

        it('Should allow user to deposit in the revsharepool, showing a balance afterwards', async () => {
			userBalanceOfRevshareTokenBeforeStaking = await LPtoken.balanceOf(user1.address);
            userBalanceOfRevsharePoolBeforeStaking = (await revSharePool.userInfo(user1.address)).amount;
            expect(userBalanceOfRevsharePoolBeforeStaking).to.equal(0);
			
			await LPtoken.connect(user1).approve(revSharePool.address, userBalanceOfRevshareTokenBeforeStaking);
            await revSharePool.connect(user1)["deposit(bool,uint256)"](false, userBalanceOfRevshareTokenBeforeStaking);

            userBalanceOfRevsharePoolAfterStaking = (await revSharePool.userInfo(user1.address)).amount;
            expect(userBalanceOfRevsharePoolAfterStaking).to.equal(userBalanceOfRevshareTokenBeforeStaking);
        })

        it('Should not accumulate rewards if not funded with ether', async () => {
            for (i=0; i<1000;i++) { //minBlocksBetweenSwaps
                await ethers.provider.send("evm_mine"); //creates a delay of minBlocksBetweenSwaps+1 blocks
                }
            
            userRewardAfterTime = await revSharePool.pendingReward(user1.address);;
            console.log("userRewardAfterTime: ", ethers.utils.formatEther(userRewardAfterTime));
            expect(userRewardAfterTime).to.be.eq(0); //will only be true on first deposit?
        })

        it('Should wait 10 blocks, then compound the LPs by calling earn(), so that vaultSharesTotal is greater after than before', async () => {
            const vaultSharesTotalBeforeCallingEarnSome = await strat1.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            maticToken = await ethers.getContractAt(token_abi, WMATIC);

            balanceMaticAtFeeAddressBeforeEarn = await ethers.provider.getBalance(revSharePool.address); //note: MATIC, not WMATIC

            // console.log(`Block number before calling earn ${await ethers.provider.getBlockNumber()}`)
            // console.log(`vaultSharesTotalBeforeCallingEarnSome: ${vaultSharesTotalBeforeCallingEarnSome}`)

            for (i=0; i<100;i++) { //minBlocksBetweenSwaps - can use this variable as an alternate to hardcoding a value
                await ethers.provider.send("evm_mine"); //creates a delay of 100 blocks - could adjust this to be minBlocksBetweenSwaps+1 blocks
            }

            await vaultHealer["earn(uint256[])"]([strat1_pid]);
            // console.log(`Block number after calling earn ${await ethers.provider.getBlockNumber()}`)

            vaultSharesTotalAfterCallingEarnSome = await strat1.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            // console.log(`vaultSharesTotalAfterCallingEarnSome: ${vaultSharesTotalAfterCallingEarnSome}`)

            const differenceInVaultSharesTotal = vaultSharesTotalAfterCallingEarnSome.sub(vaultSharesTotalBeforeCallingEarnSome);

            expect(differenceInVaultSharesTotal).to.be.gt(0); //.toNumber()
        }) 

        it('Should pay 5% of earnedAmt to the revsharepool with each earn, in MATIC', async () => {
            balanceMaticAtFeeAddressAfterEarn = await ethers.provider.getBalance(revSharePool.address); //note: MATIC, not WMATIC
            expect(balanceMaticAtFeeAddressAfterEarn).to.be.gt(balanceMaticAtFeeAddressBeforeEarn);
        })
		
	    it('Revshare pool should accumulate rewards for the staked user over time, at a rate which declines over time', async () => {
            const userRewardAtStart = await revSharePool.pendingReward(user1.address);
            console.log("userRewardAtStart: ", ethers.utils.formatEther(userRewardAtStart));
            for (i=0; i<1000;i++) { //minBlocksBetweenSwaps
                await ethers.provider.send("evm_mine"); //creates a delay of minBlocksBetweenSwaps+1 blocks
                }
            const userRewardAtMiddle = await revSharePool.pendingReward(user1.address);
            for (i=0; i<1000;i++) { //minBlocksBetweenSwaps
                await ethers.provider.send("evm_mine"); //creates a delay of minBlocksBetweenSwaps+1 blocks
                }
				
            const userRewardAtEnd = await revSharePool.pendingReward(user1.address);;
            console.log("userRewardAfterTime: ", ethers.utils.formatEther(userRewardAfterTime));
            expect(userRewardAtMiddle).to.be.gt(userRewardAtStart);
			expect(userRewardAtEnd).to.be.gt(userRewardAtMiddle);
			expect(userRewardAtEnd.sub(userRewardAtMiddle)).to.be.lt(userRewardAtMiddle.sub(userRewardAtStart));
        })
        
        it('Should withdraw 50% of LPs, taking reward as WMATIC and decreasing users pool balance correctly', async () => {
            const LPtokenBalanceBeforeFirstWithdrawal = await LPtoken.balanceOf(user1.address);
			wmatic_token = await ethers.getContractAt(token_abi, TOKEN0ADDRESS);
			const WmaticBalanceBeforeFirstWithdrawal = await wmatic_token.balanceOf(user1.address);
            const UsersStakedTokensBeforeFirstWithdrawal = (await revSharePool.userInfo(user1.address)).amount;
			const expectedRewardFromFirstWithdrawal = await revSharePool.pendingReward(user1.address);
			
            console.log(ethers.utils.formatEther(LPtokenBalanceBeforeFirstWithdrawal));
            console.log(ethers.utils.formatEther(UsersStakedTokensBeforeFirstWithdrawal));

            await revSharePool["withdraw(bool,uint128)"](true, UsersStakedTokensBeforeFirstWithdrawal.div(2)); 
            
            const LPtokenBalanceAfterFirstWithdrawal = await LPtoken.balanceOf(user1.address);
            console.log(ethers.utils.formatEther(LPtokenBalanceAfterFirstWithdrawal));

            // vaultSharesTotalAfterFirstWithdrawal = await strat1.connect(vaultHealerOwnerSigner).vaultSharesTotal() 
            const UsersStakedTokensAfterFirstWithdrawal = (await revSharePool.userInfo(user1.address)).amount;
			const WmaticBalanceAfterFirstWithdrawal = await wmatic_token.balanceOf(user1.address);
			
            // console.log(ethers.utils.formatEther(vaultSharesTotalInMaximizerBeforeWithdraw));
            // console.log(ethers.utils.formatEther(vaultSharesTotalAfterFirstWithdrawal));
            console.log(`We now have ${ethers.utils.formatEther(UsersStakedTokensAfterFirstWithdrawal)} total LP tokens left in the pool`)
            // console.log(await vaultHealer.userTotals(strat1_pid, user1.address));

            expect(LPtokenBalanceAfterFirstWithdrawal.add(UsersStakedTokensAfterFirstWithdrawal))
            .to.equal(LPtokenBalanceBeforeFirstWithdrawal.add(UsersStakedTokensBeforeFirstWithdrawal));
			//expect(WmaticBalanceAfterFirstWithdrawal.sub(WmaticBalanceBeforeFirstWithdrawal))
			//.to.equal(expectedRewardFromFirstWithdrawal);
        })
	
                // Stake a round number of LPs (e.g., 1 or 0.0001) - not a round number yet!
        it('Should deposit all of user2\'s LP tokens into the vault, increasing users stakedWantTokens by the correct amount', async () => {
            // const LPtokenBalanceOfUser2BeforeFirstDeposit = await LPtoken.balanceOf(user2.address);
            await vaultHealer["earn(uint256[])"]([strat1_pid]);
            user2InitialDeposit = await LPtoken.balanceOf(user2.address); //ethers.utils.parseEther("1500");
            const vaultSharesTotalBeforeUser2FirstDeposit = await strat1.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            console.log(`VaultSharesTotal is ${ethers.utils.formatEther(vaultSharesTotalBeforeUser2FirstDeposit)} LP tokens before user 2 deposits`)

            await LPtoken.connect(user2).approve(vaultHealer.address, user2InitialDeposit); //no, I have to approve the vaulthealer surely?
            // console.log("lp token approved by user 2")
            await vaultHealer.connect(user2)["deposit(uint256,uint256,bytes)"](strat1_pid, user2InitialDeposit, []);
            const vaultSharesTotalAfterUser2FirstDeposit = await strat1.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            const User2sSharesAfterFirstDeposit = await vaultHealer.balanceOf(user2.address, strat1_pid)
            const totalSharesAfterUser2FirstDeposit = await vaultHealer.totalSupply(strat1_pid);
            
            User2sStakedTokensAfterFirstDeposit = User2sSharesAfterFirstDeposit.mul(vaultSharesTotalAfterUser2FirstDeposit).div(totalSharesAfterUser2FirstDeposit)
            console.log(`User2 has ${ethers.utils.formatEther(User2sStakedTokensAfterFirstDeposit)} after making their first deposit`)

            console.log(`User 2 deposits ${ethers.utils.formatEther(user2InitialDeposit)} LP tokens`)
            console.log(`VaultSharesTotal is ${ethers.utils.formatEther(vaultSharesTotalAfterUser2FirstDeposit)} LP tokens after user 2 deposits`)

            expect(user2InitialDeposit).to.equal(User2sStakedTokensAfterFirstDeposit) //.sub(vaultSharesTotalBeforeUser2FirstDeposit)); //will this work for 2nd deposit? on normal masterchef?
        })

        // Deposit 100% of users LP tokens into vault, ensure balance increases as expected.
        it('Should accurately increase users shares upon second deposit by user1', async () => {
            const LPtokenBalanceBeforeSecondDeposit = await LPtoken.balanceOf(user1.address);
            await LPtoken.approve(vaultHealer.address, LPtokenBalanceBeforeSecondDeposit);
            const User1sStakedTokensBeforeSecondDeposit = await vaultHealer.balanceOf(user1.address, strat1_pid);

            await vaultHealer["deposit(uint256,uint256,bytes)"](strat1_pid, LPtokenBalanceBeforeSecondDeposit, []); //user1 (default signer) deposits LP tokens into specified strat1_pid vaulthealer
            
            const LPtokenBalanceAfterSecondDeposit = await LPtoken.balanceOf(user1.address);
            const User1sStakedTokensAfterSecondDeposit = await vaultHealer.balanceOf(user1.address, strat1_pid);

            expect(LPtokenBalanceBeforeSecondDeposit.sub(LPtokenBalanceAfterSecondDeposit)).to.closeTo(User1sStakedTokensAfterSecondDeposit.sub(User1sStakedTokensBeforeSecondDeposit), ethers.BigNumber.from(1000000000000000)); //will this work for 2nd deposit? on normal masterchef?
        })
/*
        it('Should leave zero user1 funds in revSharePool after 100% withdrawal', async () => {
            // console.log(await crystlToken.balanceOf(strat1.address))
            user = await revSharePool.userInfo(user1.address);
            userBalanceOfPoolAtEnd = user.amount;
            expect(userBalanceOfPoolAtEnd).to.equal(0);
        })
*/
    })
})

