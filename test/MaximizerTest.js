// import hre from "hardhat";

const { tokens, accounts } = require('../configs/addresses.js');
const { WMATIC, CRYSTL, DAI } = tokens.polygon;
const { FEE_ADDRESS, BURN_ADDRESS, ZERO_ADDRESS } = accounts.polygon;
const { expect } = require('chai');
const { ethers } = require('hardhat');
const { IUniRouter02_abi } = require('./abi_files/IUniRouter02_abi.js');
const { token_abi } = require('./abi_files/token_abi.js');
const { IWETH_abi } = require('./abi_files/IWETH_abi.js');
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
        [user1, user2, user3, user4, _] = await ethers.getSigners();
        /*
		Magnetite = await ethers.getContractFactory("Magnetite");
		ZapDeployer = await ethers.getContractFactory("QuartzUniV2ZapDeployer");
		VaultView = await ethers.getContractFactory("VaultView");
		magnetite = await Magnetite.deploy();
		zapDeployer = await ZapDeployer.deploy();
		vaultView = await VaultView.deploy();
		*/
		
        // vaultHealer = await ethers.getContractAt(vaultHealer_abi, VAULT_HEALER);
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
        TOKEN_OTHER = CRYSTL;
        tokenOther = await ethers.getContractAt(token_abi, TOKEN_OTHER);


		const CRYSTL_COMPOUNDER_DATA = abiCoder.encode(
			[ "address", "address", "address", "uint256", "tuple(address, uint16, uint32, bool, address, uint96)", "address[]", "uint256" ],
			[
				crystlVault[0]['want'], //wantAddress
				crystlVault[0]['masterchef'], 
				crystlVault[0]['tactic'],
				crystlVault[0]['PID'], //what is the PID of this thing in our masterhealer?
				vaultSettings.standard,
				crystlVault[0]['earned'],
				0
            ]
		);

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

        await vaultHealer.connect(vaultHealerOwnerSigner).createVault(strategyImplementation.address, CRYSTL_COMPOUNDER_DATA);
        crystl_compounder_strat_pid = await vaultHealerView.vaultLength() -1;
		strategyCrystlCompounder = await vaultHealerView.strat(crystl_compounder_strat_pid);
        strategyCrystlCompounder = await ethers.getContractAt('StrategyVHStandard', strategyCrystlCompounder);

        const MAXIMIZER_DATA = abiCoder.encode(
			[ "address", "address", "address", "uint256", "tuple(address, uint16, uint32, bool, address, uint96)", "address[]", "uint256" ],
			[
				apeSwapVaults[1]['want'],
				apeSwapVaults[1]['masterchef'],
				apeSwapVaults[1]['tactic'],
				apeSwapVaults[1]['PID'],
				vaultSettings.standard,
				apeSwapVaults[1]['earned'],
				crystl_compounder_strat_pid
			]
		);
        console.log("4");

        await vaultHealer.connect(vaultHealerOwnerSigner).createVault(strategyImplementation.address, MAXIMIZER_DATA);
        maximizer_strat_pid = await vaultHealerView.vaultLength() -1;
		strategyVHMaximizer = await vaultHealerView.strat(maximizer_strat_pid);

        strategyVHMaximizer = await ethers.getContractAt('StrategyVHStandard', strategyVHMaximizer);

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

        await network.provider.send("hardhat_setBalance", [
            user3.address,
            "0x21E19E0C9BAB2400000", //amount of 1000 in hex
        ]);

        await network.provider.send("hardhat_setBalance", [
            user4.address,
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

        if (TOKEN0ADDRESS == ethers.utils.getAddress(WMATIC) ){
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN0ADDRESS); 
            await wmatic_token.connect(user3).deposit({ value: ethers.utils.parseEther("4500") });
        } else {
            await uniswapRouter.connect(user3).swapExactETHForTokens(0, [WMATIC, TOKEN0ADDRESS], user3.address, Date.now() + 900, { value: ethers.utils.parseEther("4500") })
        }
        if (TOKEN1ADDRESS == ethers.utils.getAddress(WMATIC)) {
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN1ADDRESS); 
            await wmatic_token.connect(user3).deposit({ value: ethers.utils.parseEther("4500") });
        } else {
            await uniswapRouter.connect(user3).swapExactETHForTokens(0, [WMATIC, TOKEN1ADDRESS], user3.address, Date.now() + 900, { value: ethers.utils.parseEther("4500") })
        }

        if (TOKEN0ADDRESS == ethers.utils.getAddress(WMATIC) ){
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN0ADDRESS); 
            await wmatic_token.connect(user4).deposit({ value: ethers.utils.parseEther("3000") });
        } else {
            await uniswapRouter.connect(user4).swapExactETHForTokens(0, [WMATIC, TOKEN0ADDRESS], user4.address, Date.now() + 900, { value: ethers.utils.parseEther("3000") })
        }
        if (TOKEN1ADDRESS == ethers.utils.getAddress(WMATIC)) {
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN1ADDRESS); 
            await wmatic_token.connect(user4).deposit({ value: ethers.utils.parseEther("3000") });
        } else {
            await uniswapRouter.connect(user4).swapExactETHForTokens(0, [WMATIC, TOKEN1ADDRESS], user4.address, Date.now() + 900, { value: ethers.utils.parseEther("3000") })
        }

        await uniswapRouter.connect(user4).swapExactETHForTokens(0, [WMATIC, TOKEN_OTHER], user4.address, Date.now() + 900, { value: ethers.utils.parseEther("3000") })

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
        
        //user 3 adds liquidity to get LP tokens
        var token0BalanceUser3 = await token0.balanceOf(user3.address);
        await token0.connect(user3).approve(uniswapRouter.address, token0BalanceUser3);
        
        var token1BalanceUser3 = await token1.balanceOf(user3.address);
        await token1.connect(user3).approve(uniswapRouter.address, token1BalanceUser3);

        await uniswapRouter.connect(user3).addLiquidity(TOKEN0ADDRESS, TOKEN1ADDRESS, token0BalanceUser3, token1BalanceUser3, 0, 0, user3.address, Date.now() + 900)
        
    });

    describe(`Testing depositing into maximizer vault, compounding maximizer vault, withdrawing from maximizer vault:
    `, () => {
        // user zaps in their whole token0 balance
        // it('Should zap token0 into the vault (convert to underlying, add liquidity, and deposit to vault) - leading to an increase in vaultSharesTotal', async () => {
        //     token0 = await ethers.getContractAt(token_abi, TOKEN0ADDRESS);
        //     var token0Balance = await token0.balanceOf(user4.address);
        //     console.log("1");
        //     await token0.connect(user4).approve(quartzUniV2Zap.address, token0Balance);
        //     console.log("2");

        //     const vaultSharesTotalBeforeFirstZap = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
        //     console.log("3");

        //     await quartzUniV2Zap.connect(user4).quartzIn(maximizer_strat_pid, 0, token0.address, token0Balance); //todo - change min in amount from 0
        //     console.log("4");

        //     const vaultSharesTotalAfterFirstZap = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
        //     console.log("5");

        //     expect(vaultSharesTotalAfterFirstZap).to.be.gt(vaultSharesTotalBeforeFirstZap);
        // })
        
        // //user zaps in their whole token1 balance
        // it('Should zap token1 into the vault (convert to underlying, add liquidity, and deposit to vault) - leading to an increase in vaultSharesTotal', async () => {
        //     token1 = await ethers.getContractAt(token_abi, TOKEN1ADDRESS);
        //     var token1Balance = await token1.balanceOf(user4.address);
        //     await token1.connect(user4).approve(quartzUniV2Zap.address, token1Balance);
            
        //     const vaultSharesTotalBeforeSecondZap = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0

        //     await quartzUniV2Zap.connect(user4).quartzIn(maximizer_strat_pid, 0, token1.address, token1Balance); //To Do - change min in amount from 0
            
        //     const vaultSharesTotalAfterSecondZap = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0

        //     expect(vaultSharesTotalAfterSecondZap).to.be.gt(vaultSharesTotalBeforeSecondZap);
        // })

        // //user zaps in their whole balance of token_other
        // it('Should zap a token that is neither token0 nor token1 into the vault (convert to underlying, add liquidity, and deposit to vault) - leading to an increase in vaultSharesTotal', async () => {
        //     // assume(TOKEN_OTHER != TOKEN0 && TOKEN_OTHER != TOKEN1);
        //     tokenOther = await ethers.getContractAt(token_abi, TOKEN_OTHER);
        //     var tokenOtherBalance = await tokenOther.balanceOf(user4.address);
        //     await tokenOther.connect(user4).approve(quartzUniV2Zap.address, tokenOtherBalance);
            
        //     const vaultSharesTotalBeforeThirdZap = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0

        //     await quartzUniV2Zap.connect(user4).quartzIn(maximizer_strat_pid, 0, tokenOther.address, tokenOtherBalance); //To Do - change min in amount from 0
            
        //     const vaultSharesTotalAfterThirdZap = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0

        //     expect(vaultSharesTotalAfterThirdZap).to.be.gt(vaultSharesTotalBeforeThirdZap);
        // })

        // it('Zap out should withdraw LP tokens from vault, convert back to underlying tokens, and send back to user, increasing their token0 and token1 balances', async () => {
        //     const vaultSharesTotalBeforeZapOut = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal();
        //     var token0BalanceBeforeZapOut;
        //     var token0BalanceAfterZapOut;
        //     var token1BalanceBeforeZapOut;
        //     var token1BalanceAfterZapOut;

        //     if (TOKEN0ADDRESS == ethers.utils.getAddress(WMATIC) ){
        //         token0BalanceBeforeZapOut = await ethers.provider.getBalance(user4.address);
        //     } else {
        //         token0BalanceBeforeZapOut = await token0.balanceOf(user4.address); 
        //     }

        //     if (TOKEN1ADDRESS == ethers.utils.getAddress(WMATIC) ){
        //         token1BalanceBeforeZapOut = await ethers.provider.getBalance(user4.address);
        //     } else {
        //         token1BalanceBeforeZapOut = await token1.balanceOf(user4.address); 
        //     }

        //     await quartzUniV2Zap.connect(user4).quartzOut(maximizer_strat_pid, vaultSharesTotalBeforeZapOut); 
                        
        //     if (TOKEN0ADDRESS == ethers.utils.getAddress(WMATIC) ){
        //         token0BalanceAfterZapOut = await ethers.provider.getBalance(user4.address);
        //     } else {
        //         token0BalanceAfterZapOut = await token0.balanceOf(user4.address); 
        //     }

        //     if (TOKEN1ADDRESS == ethers.utils.getAddress(WMATIC) ){
        //         token1BalanceAfterZapOut = await ethers.provider.getBalance(user4.address);
        //     } else {
        //         token1BalanceAfterZapOut = await token1.balanceOf(user4.address); 
        //     }

        //     expect(token0BalanceAfterZapOut).to.be.gt(token0BalanceBeforeZapOut); //todo - change to check before and after zap out rather
        //     expect(token1BalanceAfterZapOut).to.be.gt(token1BalanceBeforeZapOut); //todo - change to check before and after zap out rather

        // })

        // //user should have positive balances of token0 and token1 after zap out (note - if one of the tokens is wmatic it gets paid back as matic...)
        // it('Should leave user with positive balance of token0', async () => {
        //     var token0Balance;

        //     if (TOKEN0ADDRESS == ethers.utils.getAddress(WMATIC) ){
        //         token0Balance = await ethers.provider.getBalance(user4.address);
        //     } else {
        //         token0Balance = await token0.balanceOf(user4.address); 
        //     }

        //     expect(token0Balance).to.be.gt(0); //todo - change to check before and after zap out rather
        // })

        // //user should have positive balances of token0 and token1 after zap out (note - if one of the tokens is wmatic it gets paid back as matic...)
        // it('Should leave user with positive balance of token1', async () => {
        //     var token1Balance;

        //     if (TOKEN1ADDRESS == ethers.utils.getAddress(WMATIC) ){
        //         token1Balance = await ethers.provider.getBalance(user4.address);
        //     } else {
        //         token1Balance = await token1.balanceOf(user4.address); 
        //     }

        //     expect(token1Balance).to.be.gt(0);
        // })

        // //ensure no funds left in the vault after zap out
        // it('Should leave zero user funds in vault after 100% zap out', async () => {
        //     UsersStakedTokensAfterZapOut = await vaultHealerView.stakedWantTokens(maximizer_strat_pid, user4.address);
        //     expect(UsersStakedTokensAfterZapOut.toNumber()).to.equal(0);
        // })

        // //ensure no funds left in the vault after zap out
        // it('Should leave vaultSharesTotal at zero after 100% zap out', async () => {
        //     vaultSharesTotalAfterZapOut = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal();
        //     expect(vaultSharesTotalAfterZapOut.toNumber()).to.equal(0);
        // })

        it('Should deposit user1\'s 5000 LP tokens into the vault, increasing vaultSharesTotal by the correct amount', async () => {
            // initialLPtokenBalance = await LPtoken.balanceOf(user1.address);
            user1InitialDeposit = ethers.utils.parseEther("5000");

            await LPtoken.approve(vaultHealer.address, user1InitialDeposit); //no, I have to approve the vaulthealer surely?
            LPtokenBalanceBeforeFirstDeposit = await LPtoken.balanceOf(user1.address);
            await vaultHealer["deposit(uint256,uint256)"](maximizer_strat_pid, user1InitialDeposit);
            const vaultSharesTotalAfterFirstDeposit = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            console.log(`User1 deposits ${ethers.utils.formatEther(user1InitialDeposit)} LP tokens`)
            console.log(`Vault Shares Total went up by ${ethers.utils.formatEther(vaultSharesTotalAfterFirstDeposit)} LP tokens`)

            expect(user1InitialDeposit).to.equal(vaultSharesTotalAfterFirstDeposit);
        })
        
        it('Should mint ERC1155 tokens for this user, with the maximizer_strat_pid of the strategy and equal to LP tokens deposited', async () => {
            userBalanceOfStrategyTokens = await vaultHealer.balanceOf(user1.address, maximizer_strat_pid);
            console.log(`User1 balance of ERC1155 tokens is now ${ethers.utils.formatEther(userBalanceOfStrategyTokens)} tokens`)
            // console.log(await vaultHealer.userTotals(maximizer_strat_pid, user1.address));
            expect(userBalanceOfStrategyTokens).to.eq(user1InitialDeposit); 
        })

        // Compound LPs (Call the earnSome function with this specific farm’s maximizer_strat_pid).
        // Check balance to ensure it increased as expected
        it('Should wait 10 blocks, then compound the maximizer vault by calling earnSome(), resulting in an increase in crystl in the crystl compounder', async () => {
            const vaultSharesTotalBeforeCallingEarnSome = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            console.log(`We start with ${ethers.utils.formatEther(vaultSharesTotalBeforeCallingEarnSome)} crystl tokens in the crystl compounder`)
            console.log(`We let 100 blocks pass, and then call earn...`)

            maticToken = await ethers.getContractAt(token_abi, WMATIC);

            balanceMaticAtFeeAddressBeforeEarn = await ethers.provider.getBalance(FEE_ADDRESS); //note: MATIC, not WMATIC

            // console.log(`Block number before calling earn ${await ethers.provider.getBlockNumber()}`)
            // console.log(`vaultSharesTotalBeforeCallingEarnSome: ${vaultSharesTotalBeforeCallingEarnSome}`)

            for (i=0; i<100;i++) { //minBlocksBetweenSwaps - can use this variable as an alternate to hardcoding a value
                await ethers.provider.send("evm_mine"); //creates a delay of 100 blocks - could adjust this to be minBlocksBetweenSwaps+1 blocks
            }

            await vaultHealer.earn(maximizer_strat_pid);
            // console.log(`Block number after calling earn ${await ethers.provider.getBlockNumber()}`)

            vaultSharesTotalAfterCallingEarnSome = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            console.log(`After the earn call we have ${ethers.utils.formatEther(vaultSharesTotalAfterCallingEarnSome)} crystl tokens in the crystl compounder`)
            // console.log(await vaultHealer.userTotals(maximizer_strat_pid, user1.address));

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
        it('Should wait 10 blocks, then compound the CRYSTL Compounder by calling earnSome(), so that vaultSharesTotal is greater after than before', async () => {
            const vaultSharesTotalBeforeCallingEarnSome = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            const wantLockedTotalBeforeCallingEarnSome = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).wantLockedTotal()

            console.log(`Before calling earn on the CRYSTL compounder, we have ${ethers.utils.formatEther(vaultSharesTotalBeforeCallingEarnSome)} CRYSTL tokens in it`)
            console.log(`We let 100 blocks pass...`)
            // console.log(`Block number before calling earn ${await ethers.provider.getBlockNumber()}`)
            console.log(`vaultSharesTotalBeforeCallingEarnSome: ${vaultSharesTotalBeforeCallingEarnSome}`)

            for (i=0; i<500;i++) { //minBlocksBetweenSwaps - can use this variable as an alternate to hardcoding a value
                await ethers.provider.send("evm_mine"); //creates a delay of 100 blocks - could adjust this to be minBlocksBetweenSwaps+1 blocks
            }

            await vaultHealer.earnSome([crystl_compounder_strat_pid]);
            // console.log(`Block number after calling earn ${await ethers.provider.getBlockNumber()}`)

            vaultSharesTotalInCrystalCompounderAfterCallingEarnSome = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            console.log(`vaultSharesTotalInCrystalCompounderAfterCallingEarnSome: ${vaultSharesTotalInCrystalCompounderAfterCallingEarnSome}`)
            console.log(`After calling earn on the CRYSTL compounder, we have ${ethers.utils.formatEther(vaultSharesTotalInCrystalCompounderAfterCallingEarnSome)} CRYSTL tokens in it`)
            // console.log(await vaultHealer.userTotals(maximizer_strat_pid, user1.address));

            const differenceInVaultSharesTotal = vaultSharesTotalInCrystalCompounderAfterCallingEarnSome.sub(vaultSharesTotalBeforeCallingEarnSome);

            expect(differenceInVaultSharesTotal).to.be.gt(0); //.toNumber()
        }) 
        
        // Unstake 50% of LPs. 
        // Check transaction to ensure withdraw fee amount is as expected and amount withdrawn in as expected
        it('Should withdraw 50% of LPs with correct withdraw fee amount (0.1%) and decrease users stakedWantTokens balance correctly', async () => {
            const LPtokenBalanceBeforeFirstWithdrawal = await LPtoken.balanceOf(user1.address);
            const UsersStakedTokensBeforeFirstWithdrawal = await vaultHealerView.stakedWantTokens(maximizer_strat_pid, user1.address);

            vaultSharesTotalInMaximizerBeforeWithdraw = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            crystlToken = await ethers.getContractAt(token_abi, CRYSTL);
            user1CrystlBalanceBeforeWithdraw = await crystlToken.balanceOf(user1.address);

            console.log(`User 1 withdraws ${ethers.utils.formatEther(UsersStakedTokensBeforeFirstWithdrawal.div(2))} LP tokens from the maximizer vault`)

            await vaultHealer["withdraw(uint256,uint256)"](maximizer_strat_pid, UsersStakedTokensBeforeFirstWithdrawal.div(2)); 
            
            const LPtokenBalanceAfterFirstWithdrawal = await LPtoken.balanceOf(user1.address);
            // console.log(ethers.utils.formatEther(LPtokenBalanceAfterFirstWithdrawal));

            vaultSharesTotalAfterFirstWithdrawal = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() 
            // console.log(ethers.utils.formatEther(vaultSharesTotalInMaximizerBeforeWithdraw));
            // console.log(ethers.utils.formatEther(vaultSharesTotalAfterFirstWithdrawal));
            console.log(`We now have ${ethers.utils.formatEther(vaultSharesTotalAfterFirstWithdrawal)} total LP tokens left in the maximizer vault`)
            // console.log(await vaultHealer.userTotals(maximizer_strat_pid, user1.address));

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
        it('Should return CRYSTL harvest to user 1 when they withdraw (above test)', async () => {
            user1CrystlBalanceAfterWithdraw = await crystlToken.balanceOf(user1.address);
            console.log(`The user got ${ethers.utils.formatEther((user1CrystlBalanceAfterWithdraw).sub(user1CrystlBalanceBeforeWithdraw))} CRYSTL tokens back from the maximizer vault`)

            expect(user1CrystlBalanceAfterWithdraw).to.be.gt(user1CrystlBalanceBeforeWithdraw);
        })

        // Stake a round number of LPs (e.g., 1 or 0.0001) - not a round number yet!
        it('Should deposit 1500 of user2\'s LP tokens into the vault, increasing vaultSharesTotal by the correct amount', async () => {
            // const LPtokenBalanceOfUser2BeforeFirstDeposit = await LPtoken.balanceOf(user2.address);
            user2InitialDeposit = ethers.utils.parseEther("1500");
            const vaultSharesTotalBeforeUser2FirstDeposit = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            console.log(`VaultSharesTotal is ${ethers.utils.formatEther(vaultSharesTotalBeforeUser2FirstDeposit)} LP tokens before user 2 deposits`)

            await LPtoken.connect(user2).approve(vaultHealer.address, user2InitialDeposit); //no, I have to approve the vaulthealer surely?
            // console.log("lp token approved by user 2")
            await vaultHealer.connect(user2)["deposit(uint256,uint256)"](maximizer_strat_pid, user2InitialDeposit);
            const vaultSharesTotalAfterUser2FirstDeposit = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
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
            console.log(`After the earn call we have ${ethers.utils.formatEther(vaultSharesTotalAfterCallingEarnSome)} crystl tokens in the crystl compounder`)

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
        it('Should wait 10 blocks, then compound the CRYSTL Compounder by calling earnSome(), so that vaultSharesTotal is greater after than before', async () => {
            const vaultSharesTotalBeforeCallingEarnSome = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            const wantLockedTotalBeforeCallingEarnSome = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).wantLockedTotal()

            console.log(`Before calling earn on the CRYSTL compounder, we have ${ethers.utils.formatEther(vaultSharesTotalBeforeCallingEarnSome)} CRYSTL tokens in it`)
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
            console.log(`After calling earn on the CRYSTL compounder, we have ${ethers.utils.formatEther(vaultSharesTotalInCrystalCompounderAfterCallingEarnSome)} CRYSTL tokens in it`)
            const wantLockedTotalAfterCallingEarnSome = await strategyCrystlCompounder.wantLockedTotal() //.connect(vaultHealerOwnerSigner)

            const differenceInVaultSharesTotal = vaultSharesTotalInCrystalCompounderAfterCallingEarnSome.sub(vaultSharesTotalBeforeCallingEarnSome);

            expect(differenceInVaultSharesTotal).to.be.gt(0); //.toNumber()
        }) 
        
        // Unstake 50% of LPs. 
        // Check transaction to ensure withdraw fee amount is as expected and amount withdrawn in as expected
        it('Should withdraw 50% of user 2 LPs with correct withdraw fee amount (0.1%) and decrease users stakedWantTokens balance correctly', async () => {
            const LPtokenBalanceBeforeFirstWithdrawal = await LPtoken.balanceOf(user2.address);
            const UsersStakedTokensBeforeFirstWithdrawal = await vaultHealerView.stakedWantTokens(maximizer_strat_pid, user2.address);
            // console.log(ethers.utils.formatEther(UsersStakedTokensBeforeFirstWithdrawal));

            vaultSharesTotalInMaximizerBeforeWithdraw = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            crystlToken = await ethers.getContractAt(token_abi, CRYSTL);
            user2CrystlBalanceBeforeWithdraw = await crystlToken.balanceOf(user2.address);
            // console.log("user1CrystlBalanceBeforeWithdraw");
            // console.log(user1CrystlBalanceBeforeWithdraw);
            console.log(`User 2 withdraws ${ethers.utils.formatEther(UsersStakedTokensBeforeFirstWithdrawal.div(2))} LP tokens from the maximizer vault`)

            await vaultHealer.connect(user2)["withdraw(uint256,uint256)"](maximizer_strat_pid, UsersStakedTokensBeforeFirstWithdrawal.div(2)); 
            
            const LPtokenBalanceAfterFirstWithdrawal = await LPtoken.balanceOf(user2.address);
            // console.log(ethers.utils.formatEther(LPtokenBalanceAfterFirstWithdrawal));

            vaultSharesTotalAfterFirstWithdrawal = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() 
            // console.log(ethers.utils.formatEther(vaultSharesTotalInMaximizerBeforeWithdraw));
            // console.log(ethers.utils.formatEther(vaultSharesTotalAfterFirstWithdrawal));
            console.log(`We now have ${ethers.utils.formatEther(vaultSharesTotalAfterFirstWithdrawal)} total LP tokens left in the maximizer vault`)

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
        it('Should return CRYSTL harvest to user 2 when they withdraw (above test)', async () => {
            user2CrystlBalanceAfterWithdraw = await crystlToken.balanceOf(user2.address);
            // console.log("user1CrystlBalanceAfterWithdraw");
            // console.log(user1CrystlBalanceAfterWithdraw);
            console.log(`The user got ${ethers.utils.formatEther((user2CrystlBalanceAfterWithdraw).sub(user2CrystlBalanceBeforeWithdraw))} CRYSTL tokens back from the maximizer vault`)

            expect(user2CrystlBalanceAfterWithdraw).to.be.gt(user2CrystlBalanceBeforeWithdraw);
        })

               // Unstake 50% of LPs. 
        // Check transaction to ensure withdraw fee amount is as expected and amount withdrawn in as expected
        it('Should withdraw the other 50% of user 2 LPs with correct withdraw fee amount (0.1%) and decrease users stakedWantTokens balance correctly', async () => {
            const LPtokenBalanceBeforeSecondWithdrawal = await LPtoken.balanceOf(user2.address);
            const UsersStakedTokensBeforeSecondWithdrawal = await vaultHealerView.stakedWantTokens(maximizer_strat_pid, user2.address);
            // console.log(ethers.utils.formatEther(UsersStakedTokensBeforeSecondWithdrawal));

            vaultSharesTotalInMaximizerBeforeWithdraw = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            crystlToken = await ethers.getContractAt(token_abi, CRYSTL);
            user2CrystlBalanceBeforeWithdraw = await crystlToken.balanceOf(user2.address);
            // console.log("user1CrystlBalanceBeforeWithdraw");
            // console.log(user1CrystlBalanceBeforeWithdraw);
            console.log(`User 2 withdraws ${ethers.utils.formatEther(UsersStakedTokensBeforeSecondWithdrawal)} LP tokens from the maximizer vault`)

            await vaultHealer.connect(user2)["withdraw(uint256,uint256)"](maximizer_strat_pid, UsersStakedTokensBeforeSecondWithdrawal); 
            
            const LPtokenBalanceAfterSecondWithdrawal = await LPtoken.balanceOf(user2.address);
            // console.log(ethers.utils.formatEther(LPtokenBalanceAfterSecondWithdrawal));

            vaultSharesTotalAfterSecondWithdrawal = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() 
            // console.log(ethers.utils.formatEther(vaultSharesTotalInMaximizerBeforeWithdraw));
            // console.log(ethers.utils.formatEther(vaultSharesTotalAfterSecondWithdrawal));
            console.log(`We now have ${ethers.utils.formatEther(vaultSharesTotalAfterSecondWithdrawal)} total LP tokens left in the maximizer vault`)

            expect(LPtokenBalanceAfterSecondWithdrawal.sub(LPtokenBalanceBeforeSecondWithdrawal))
            .to.equal(
                (vaultSharesTotalInMaximizerBeforeWithdraw.sub(vaultSharesTotalAfterSecondWithdrawal))
                .sub((WITHDRAW_FEE_FACTOR_MAX.sub(withdrawFeeFactor))
                .mul(vaultSharesTotalInMaximizerBeforeWithdraw.sub(vaultSharesTotalAfterSecondWithdrawal))
                .div(WITHDRAW_FEE_FACTOR_MAX))
                )
                ;
        })

        // withdraw should also cause crystl to be returned to the user (all of it)
        it('Should return CRYSTL harvest to user 2 when they withdraw (above test)', async () => {
            user2CrystlBalanceAfterWithdraw = await crystlToken.balanceOf(user2.address);
            // console.log("user1CrystlBalanceAfterWithdraw");
            // console.log(user1CrystlBalanceAfterWithdraw);
            console.log(`The user got ${ethers.utils.formatEther((user2CrystlBalanceAfterWithdraw).sub(user2CrystlBalanceBeforeWithdraw))} CRYSTL tokens back from the maximizer vault`)

            expect(user2CrystlBalanceAfterWithdraw).to.be.gt(user2CrystlBalanceBeforeWithdraw);
        })

        it('Should deposit 1500 LP tokens from user into the vault, increasing vaultSharesTotal by the correct amount', async () => {
            // const LPtokenBalanceOfUser2BeforeFirstDeposit = await LPtoken.balanceOf(user3.address);
            user3InitialDeposit = ethers.utils.parseEther("1500");
            const vaultSharesTotalBeforeUser3FirstDeposit = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            console.log(`VaultSharesTotal is ${ethers.utils.formatEther(vaultSharesTotalBeforeUser3FirstDeposit)} LP tokens before user 3 deposits`)

            await LPtoken.connect(user3).approve(vaultHealer.address, user3InitialDeposit); //no, I have to approve the vaulthealer surely?
            // console.log("lp token approved by user 2")
            await vaultHealer.connect(user3)["deposit(uint256,uint256)"](maximizer_strat_pid, user3InitialDeposit);
            const user3vaultSharesTotalAfterUser3FirstDeposit = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            console.log(`User 3 deposits ${ethers.utils.formatEther(user3InitialDeposit)} LP tokens`);
            console.log(`VaultSharesTotal is ${ethers.utils.formatEther(user3vaultSharesTotalAfterUser3FirstDeposit)} LP tokens after user 3 deposits`)

            expect(user3InitialDeposit).to.equal(user3vaultSharesTotalAfterUser3FirstDeposit.sub(vaultSharesTotalBeforeUser3FirstDeposit)); //will this work for 2nd deposit? on normal masterchef?
        })

        it('Should mint ERC1155 tokens for this user, with the maximizer_strat_pid of the strategy and equal to LP tokens deposited', async () => {
            userBalanceOfStrategyTokens = await vaultHealer.balanceOf(user3.address, maximizer_strat_pid);
            console.log(`User3 balance of ERC1155 tokens is now ${ethers.utils.formatEther(userBalanceOfStrategyTokens)} tokens`)
            expect(userBalanceOfStrategyTokens).to.eq(user3InitialDeposit); 
        })

        it('Should deposit 15000 CRYSTL tokens from user 4 directly into the crystl compounder vault, increasing vaultSharesTotal by the correct amount', async () => {
            // const LPtokenBalanceOfUser2BeforeFirstDeposit = await LPtoken.balanceOf(user3.address);
            user4InitialDeposit = ethers.utils.parseEther("15000");
            const vaultSharesTotalBeforeUser4FirstDeposit = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            console.log(`VaultSharesTotal is ${ethers.utils.formatEther(vaultSharesTotalBeforeUser4FirstDeposit)} CRYSTL tokens before user 4 deposits`)

            await tokenOther.connect(user4).approve(vaultHealer.address, user4InitialDeposit); //no, I have to approve the vaulthealer surely?
            // console.log("lp token approved by user 2")
            await vaultHealer.connect(user4)["deposit(uint256,uint256)"](crystl_compounder_strat_pid, user4InitialDeposit);
            const vaultSharesTotalAfterUser4FirstDeposit = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            console.log(`User 4 deposits ${ethers.utils.formatEther(user4InitialDeposit)} CRYSTL tokens`);
            console.log(`VaultSharesTotal is ${ethers.utils.formatEther(vaultSharesTotalAfterUser4FirstDeposit)} CRYSTL tokens after user 4 deposits`)

            expect(user4InitialDeposit).to.equal(vaultSharesTotalAfterUser4FirstDeposit.sub(vaultSharesTotalBeforeUser4FirstDeposit)); //will this work for 2nd deposit? on normal masterchef?
        })

        // Compound LPs (Call the earnSome function with this specific farm’s maximizer_strat_pid).
        // Check balance to ensure it increased as expected
        it('Should wait 10 blocks, then compound the maximizer vault by calling earnSome(), resulting in an increase in crystl in the crystl compounder', async () => {
            const vaultSharesTotalBeforeCallingEarnSome = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            console.log(`We start with ${ethers.utils.formatEther(vaultSharesTotalBeforeCallingEarnSome)} crystl tokens in the crystl compounder`)
            console.log(`We let 100 blocks pass, and then call earn...`)

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
            console.log(`After the earn call we have ${ethers.utils.formatEther(vaultSharesTotalAfterCallingEarnSome)} crystl tokens in the crystl compounder`)

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
        it('Should wait 10 blocks, then compound the CRYSTL Compounder by calling earnSome(), so that vaultSharesTotal is greater after than before', async () => {
            const vaultSharesTotalBeforeCallingEarnSome = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            const wantLockedTotalBeforeCallingEarnSome = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).wantLockedTotal()

            console.log(`Before calling earn on the CRYSTL compounder, we have ${ethers.utils.formatEther(vaultSharesTotalBeforeCallingEarnSome)} CRYSTL tokens in it`)
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
            console.log(`After calling earn on the CRYSTL compounder, we have ${ethers.utils.formatEther(vaultSharesTotalInCrystalCompounderAfterCallingEarnSome)} CRYSTL tokens in it`)
            const wantLockedTotalAfterCallingEarnSome = await strategyCrystlCompounder.wantLockedTotal() //.connect(vaultHealerOwnerSigner)

            const differenceInVaultSharesTotal = vaultSharesTotalInCrystalCompounderAfterCallingEarnSome.sub(vaultSharesTotalBeforeCallingEarnSome);

            expect(differenceInVaultSharesTotal).to.be.gt(0); //.toNumber()
        }) 
        
        // Unstake 50% of LPs. 
        // Check transaction to ensure withdraw fee amount is as expected and amount withdrawn in as expected
        it('Should withdraw 50% of user 3 LPs with correct withdraw fee amount (0.1%) and decrease users stakedWantTokens balance correctly', async () => {
            const LPtokenBalanceBeforeFirstWithdrawal = await LPtoken.balanceOf(user3.address);
            const UsersStakedTokensBeforeFirstWithdrawal = await vaultHealerView.stakedWantTokens(maximizer_strat_pid, user3.address);
            // console.log(ethers.utils.formatEther(UsersStakedTokensBeforeFirstWithdrawal));

            vaultSharesTotalInMaximizerBeforeWithdraw = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            crystlToken = await ethers.getContractAt(token_abi, CRYSTL);
            user3CrystlBalanceBeforeWithdraw = await crystlToken.balanceOf(user3.address);
            // console.log("user1CrystlBalanceBeforeWithdraw");
            // console.log(user1CrystlBalanceBeforeWithdraw);
            console.log(`User 3 withdraws ${ethers.utils.formatEther(UsersStakedTokensBeforeFirstWithdrawal.div(2))} LP tokens from the maximizer vault`)

            await vaultHealer.connect(user3)["withdraw(uint256,uint256)"](maximizer_strat_pid, UsersStakedTokensBeforeFirstWithdrawal.div(2));  
            
            const LPtokenBalanceAfterFirstWithdrawal = await LPtoken.balanceOf(user3.address);
            // console.log(ethers.utils.formatEther(LPtokenBalanceAfterFirstWithdrawal));

            vaultSharesTotalAfterFirstWithdrawal = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() 
            // console.log(ethers.utils.formatEther(vaultSharesTotalInMaximizerBeforeWithdraw));
            // console.log(ethers.utils.formatEther(vaultSharesTotalAfterFirstWithdrawal));
            console.log(`We now have ${ethers.utils.formatEther(vaultSharesTotalAfterFirstWithdrawal)} total LP tokens left in the maximizer vault`)

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
        it('Should return CRYSTL harvest to user when they withdraw (above test)', async () => {
            user3CrystlBalanceAfterWithdraw = await crystlToken.balanceOf(user3.address);
            // console.log("user1CrystlBalanceAfterWithdraw");
            // console.log(user1CrystlBalanceAfterWithdraw);
            console.log(`The user got ${ethers.utils.formatEther((user3CrystlBalanceAfterWithdraw).sub(user3CrystlBalanceBeforeWithdraw))} CRYSTL tokens back from the maximizer vault`)

            expect(user3CrystlBalanceAfterWithdraw).to.be.gt(user3CrystlBalanceBeforeWithdraw);
        })

        it('Should transfer 1155 tokens from user 3 to user 1, updating shares accurately', async () => {
            const User3StakedTokensBeforeTransfer = await vaultHealerView.stakedWantTokens(maximizer_strat_pid, user3.address);
            const User1StakedTokensBeforeTransfer = await vaultHealerView.stakedWantTokens(maximizer_strat_pid, user1.address);

            vaultHealer.connect(user3).setApprovalForAll(user1.address, true);

            await vaultHealer.connect(user3).safeTransferFrom(
                user3.address,
                user1.address,
                maximizer_strat_pid,
                User3StakedTokensBeforeTransfer,
                0);

            const User3StakedTokensAfterTransfer = await vaultHealerView.stakedWantTokens(maximizer_strat_pid, user3.address);
            const User1StakedTokensAfterTransfer = await vaultHealerView.stakedWantTokens(maximizer_strat_pid, user1.address);

            expect(User3StakedTokensBeforeTransfer.sub(User3StakedTokensAfterTransfer)).to.eq(User1StakedTokensAfterTransfer.sub(User1StakedTokensBeforeTransfer))
        })

        // // it('Should increase rewardDebt when you receive transferred tokens', async () => {
        // //     // const User1RewardDebtAfterTransfer = await vaultHealerView.rewardDebt(maximizer_strat_pid, user1.address);

        // //     expect(User1RewardDebtAfterTransfer).to.be.gt(User1RewardDebtBeforeTransfer);
        // // })

        // withdraw should also cause crystl to be returned to the user (all of it)
        it('Should return CRYSTL harvest to user when they withdraw (above test)', async () => {
            user3CrystlBalanceAfterWithdraw = await crystlToken.balanceOf(user3.address);
            // console.log("user1CrystlBalanceAfterWithdraw");
            // console.log(user1CrystlBalanceAfterWithdraw);
            console.log(`The user got ${ethers.utils.formatEther((user3CrystlBalanceAfterWithdraw).sub(user3CrystlBalanceBeforeWithdraw))} CRYSTL tokens back from the maximizer vault`)

            expect(user3CrystlBalanceAfterWithdraw).to.be.gt(user3CrystlBalanceBeforeWithdraw);
        })

        // Deposit 100% of users LP tokens into vault, ensure balance increases as expected.
        it('Should accurately increase vaultSharesTotal upon second deposit of 200 LP tokens by user1', async () => {
            user1SecondDepositAmount = ethers.utils.parseEther("200");
            await LPtoken.approve(vaultHealer.address, user1SecondDepositAmount);

            const vaultSharesTotalBeforeSecondDeposit = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0
            console.log(`VaultSharesTotal is ${ethers.utils.formatEther(vaultSharesTotalBeforeSecondDeposit)} LP tokens before user 1 makes their 2nd deposit`)

            await vaultHealer["deposit(uint256,uint256)"](maximizer_strat_pid, user1SecondDepositAmount); //user1 (default signer) deposits LP tokens into specified maximizer_strat_pid vaulthealer
            console.log(`User 1 deposits ${ethers.utils.formatEther(user1SecondDepositAmount)} LP tokens`);

            const vaultSharesTotalAfterSecondDeposit = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0;
            console.log(`VaultSharesTotal is ${ethers.utils.formatEther(vaultSharesTotalAfterSecondDeposit)} LP tokens after user 1 makes their 2nd deposit`)

            expect(user1SecondDepositAmount).to.equal(vaultSharesTotalAfterSecondDeposit.sub(vaultSharesTotalBeforeSecondDeposit)); //will this work for 2nd deposit? on normal masterchef?
        })
        

        // Withdraw 100%
        it('Should withdraw remaining user1 balance back to user1, with all of it staked in boosting pool, minus withdrawal fee (0.1%)', async () => {
            userBalanceOfStrategyTokensBeforeStaking = await vaultHealer.balanceOf(user1.address, maximizer_strat_pid);
            console.log(`User1 now has ${ethers.utils.formatEther(userBalanceOfStrategyTokensBeforeStaking)} tokens in the maximizer vault`)

            const LPtokenBalanceBeforeFinalWithdrawal = await LPtoken.balanceOf(user1.address)
            // console.log("LPtokenBalanceBeforeFinalWithdrawal - user1")
            // console.log(ethers.utils.formatEther(LPtokenBalanceBeforeFinalWithdrawal))

            const UsersStakedTokensBeforeFinalWithdrawal = await vaultHealerView.stakedWantTokens(maximizer_strat_pid, user1.address);
            // console.log("UsersStakedTokensBeforeFinalWithdrawal - user1")
            // console.log(ethers.utils.formatEther(UsersStakedTokensBeforeFinalWithdrawal))

            await vaultHealer["withdrawAll(uint256)"](maximizer_strat_pid); //user1 (default signer) deposits 1 of LP tokens into maximizer_strat_pid 0 of vaulthealer
            
            const LPtokenBalanceAfterFinalWithdrawal = await LPtoken.balanceOf(user1.address);
            // console.log("LPtokenBalanceAfterFinalWithdrawal - user1")
            // console.log(ethers.utils.formatEther(LPtokenBalanceAfterFinalWithdrawal))

            UsersStakedTokensAfterFinalWithdrawal = await vaultHealerView.stakedWantTokens(maximizer_strat_pid, user1.address);
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

        // Withdraw 100% of user 4 deposit into crystl compounder
        it('Should withdraw remaining user4 balance back to user4, minus withdrawal fee (0.1%)', async () => {
            user4BalanceOfCrystlCompounderTokensBeforeStaking = await vaultHealer.balanceOf(user4.address, crystl_compounder_strat_pid);
            console.log(`User4 now has ${ethers.utils.formatEther(user4BalanceOfCrystlCompounderTokensBeforeStaking)} tokens in the crystl compounder vault`)

            const CRYSTLBalanceBeforeUser4Withdrawal = await tokenOther.balanceOf(user4.address)
            console.log("CRYSTLBalanceBeforeUser4Withdrawal - user4")
            console.log(ethers.utils.formatEther(CRYSTLBalanceBeforeUser4Withdrawal))

            const User4StakedTokensBeforeFinalWithdrawal = await vaultHealerView.stakedWantTokens(crystl_compounder_strat_pid, user4.address);
            console.log("User4StakedTokensBeforeFinalWithdrawal - user4")
            console.log(ethers.utils.formatEther(User4StakedTokensBeforeFinalWithdrawal))

            await vaultHealer.connect(user4)["withdrawAll(uint256)"](crystl_compounder_strat_pid); //user1 (default signer) deposits 1 of LP tokens into maximizer_strat_pid 0 of vaulthealer
            
            const CRYSTLBalanceAfterFinalWithdrawal = await tokenOther.balanceOf(user4.address);
            console.log("CRYSTLBalanceAfterFinalWithdrawal - user4")
            console.log(ethers.utils.formatEther(CRYSTLBalanceAfterFinalWithdrawal))

            User4StakedTokensAfterFinalWithdrawal = await vaultHealerView.stakedWantTokens(crystl_compounder_strat_pid, user4.address);
            console.log("User4StakedTokensAfterFinalWithdrawal - user4")
            console.log(ethers.utils.formatEther(User4StakedTokensAfterFinalWithdrawal))

            expect(CRYSTLBalanceAfterFinalWithdrawal.sub(CRYSTLBalanceBeforeUser4Withdrawal))
            .to.equal(
                (User4StakedTokensBeforeFinalWithdrawal.sub(User4StakedTokensAfterFinalWithdrawal))
                // .sub(
                //     (WITHDRAW_FEE_FACTOR_MAX.sub(withdrawFeeFactor))
                //     .mul(User4StakedTokensBeforeFinalWithdrawal.sub(User4StakedTokensAfterFinalWithdrawal))
                //     .div(WITHDRAW_FEE_FACTOR_MAX)
                // )
                );
        })

        it('Should leave zero crystl in the crystl compounder once all 3 users have fully withdrawn their funds', async () => {
            vaultSharesTotalInCrystlCompounderAtEnd = await strategyCrystlCompounder.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            vaultSharesTotalInMaximizerAtEnd = await strategyVHMaximizer.connect(vaultHealerOwnerSigner).vaultSharesTotal()

            console.log(`There are now ${ethers.utils.formatEther(vaultSharesTotalInMaximizerAtEnd)} LP tokens in the maximizer and 
            ${ethers.utils.formatEther(vaultSharesTotalInCrystlCompounderAtEnd)} crystl tokens left in the compounder`);
            expect(vaultSharesTotalInCrystlCompounderAtEnd).to.eq(0);
        })
    })
})

