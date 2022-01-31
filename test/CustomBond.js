// import hre from "hardhat";

const { tokens, accounts, lps, routers } = require('../configs/addresses.js');
const { WMATIC, CRYSTL, DAI } = tokens.polygon;
const { MATIC_CRYSTL_APE_LP } = lps.polygon;
const { APESWAP_ROUTER } = routers.polygon;
const { FEE_ADDRESS, BURN_ADDRESS, ZERO_ADDRESS } = accounts.polygon;
const { expect } = require('chai');
const { ethers } = require('hardhat');
const { IUniRouter02_abi } = require('./abi_files/IUniRouter02_abi.js');
const { token_abi } = require('./abi_files/token_abi.js');
const { IWETH_abi } = require('./abi_files/IWETH_abi.js');

// const { IMasterchef_abi } = require('./IMasterchef_abi.js');
const { IUniswapV2Pair_abi } = require('./abi_files/IUniswapV2Pair_abi.js');


describe(`Testing Custom Bond`, () => {
    before(async () => {
        [user1, user2, user3, _] = await ethers.getSigners();

        CustomTreasury = await ethers.getContractFactory("CustomTreasury", {
        });

        customTreasury = await CustomTreasury.deploy(
            CRYSTL, //address _payoutToken,  todo - what should this be? we bond crystl and pay out in?
            user1.address, //address _initialOwner
        );

        CustomBond = await ethers.getContractFactory("CustomBond", {
        });
        
        customBond = await CustomBond.deploy(        
            customTreasury.address, //address _customTreasury, 
            MATIC_CRYSTL_APE_LP, //address _principalToken, CRYSTL-CRO LP
            user1.address, //address _initialOwner
            );
        
        customTreasury.toggleBondContract(customBond.address);
        
        customBond.setBondTerms(0, 46200); //PARAMETER = { VESTING, PAYOUT, DEBT }

        customBond.initializeBond(
            250000, //uint _controlVariable, 
            46200, //uint _vestingTerm,
            0, //1351351, //uint _minimumPrice,
            100000000000, //uint _maxPayout,
            "100000000000000000000000", //uint _maxDebt,
            "690000000000000000000", //uint _initialDebt
        )
        
        // console.log("await customBond.bondPrice()");
        // console.log(await customBond.bondPrice());

        // console.log("await customBond.trueBondPrice()");
        // console.log(await customBond.trueBondPrice());

        // console.log("await customBond.maxPayout()");
        // console.log(await customBond.maxPayout());



        // console.log("await customBond.debtRatio()");
        // console.log(await customBond.debtRatio());

        // console.log("await customBond.currentDebt()");
        // console.log(await customBond.currentDebt());

        // console.log("await customBond.debtDecay()");
        // console.log(await customBond.debtDecay());

        // console.log("await customBond.percentVestedFor(user1.address)");
        // console.log(await customBond.percentVestedFor(user1.address));

        // console.log("await customBond.pendingPayoutFor(user1.address)");
        // console.log(await customBond.pendingPayoutFor(user1.address));


        LPtoken = await ethers.getContractAt(IUniswapV2Pair_abi, MATIC_CRYSTL_APE_LP);
        TOKEN0ADDRESS = await LPtoken.token0()
        TOKEN1ADDRESS = await LPtoken.token1()
    
        uniswapRouter = await ethers.getContractAt(IUniRouter02_abi, APESWAP_ROUTER);

        await network.provider.send("hardhat_setBalance", [
            user1.address,
            "0x21E19E0C9BAB2400000", //amount of 1000 in hex
        ]);

        await network.provider.send("hardhat_setBalance", [
            user2.address,
            "0x84595161401484A000000", //amount of 1000 in hex
        ]);

         //fund the treasury with reward token, Crystl 
         crystlToken = await ethers.getContractAt(token_abi, CRYSTL);
        //  await setTokenBalanceInStorage(crystlToken, customTreasury.address, "10000");

         await uniswapRouter.connect(user2).swapExactETHForTokens(0, [WMATIC, CRYSTL], customTreasury.address, Date.now() + 900, { value: ethers.utils.parseEther("9900000") })
        // I think I'm losing out massively to slippage here...

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
 
        //create instances of token0 and token1
        token0 = await ethers.getContractAt(token_abi, TOKEN0ADDRESS);
        token1 = await ethers.getContractAt(token_abi, TOKEN1ADDRESS);
        
        //user 1 adds liquidity to get LP tokens
        var token0BalanceUser1 = await token0.balanceOf(user1.address);
        await token0.approve(uniswapRouter.address, token0BalanceUser1);
        
        var token1BalanceUser1 = await token1.balanceOf(user1.address);
        await token1.approve(uniswapRouter.address, token1BalanceUser1);
        
        await uniswapRouter.addLiquidity(TOKEN0ADDRESS, TOKEN1ADDRESS, token0BalanceUser1, token1BalanceUser1, 0, 0, user1.address, Date.now() + 900)
        

        
    });

    describe(`Testing depositing into the bond, running through some of the vesting period, redeeming CRYSTL from the bond:
    `, () => {
        it('Should deposit user1\'s LP tokens into the bond, increasing the bonds currentDebt by the amount of LP tokens deposited', async () => {
            //init contract calls
            
            initialLPtokenBalance = "1000000000000000000";

            initialDebtBeforeDeposit = await customBond.currentDebt();

            initpayoutFor = await customBond.payoutFor(initialLPtokenBalance);

            initdebtRatio = await customBond.debtRatio();

            initUserCrystlBalance = await crystlToken.balanceOf(user1.address);

            console.log(`Initial LP Balance for USER1 is ${ethers.utils.formatEther(initialLPtokenBalance)} LP tokens`);
            console.log(`Initial CRYSTL balance for user1 is ${ethers.utils.formatEther(initialLPtokenBalance)} CRYSTL`);
            console.log(`Initial Debt for the bond is ${ethers.utils.formatEther(initialDebtBeforeDeposit)} LP tokens`);
            console.log(`Initial payout for 1 LP token is ${ethers.utils.formatEther(initpayoutFor)} CRYSTL`);
            console.log(`Initial Debt Ratio for the bond is ${ethers.utils.formatEther(initdebtRatio)}`);


            //User1 approves their tokens and deposits them to CustomBond
            await LPtoken.connect(user1).approve(customBond.address, initialLPtokenBalance);

            await customBond.deposit(initialLPtokenBalance, 1000000000000000, user1.address); //uint _maxPrice

            debtAfterDeposit = await customBond.currentDebt();

            debtRatioAfterDeposit = await customBond.debtRatio();

            payoutForAfterDeposit = await customBond.payoutFor(initialLPtokenBalance);

            initPendingPayout = await customBond.pendingPayoutFor(user1.address);

            console.log(`User1 has deposited ${ethers.utils.formatEther(initialLPtokenBalance)} LP tokens`)
            console.log(`Payout for 1LP token is now  ${ethers.utils.formatEther(payoutForAfterDeposit)} CRYSTL`);
            console.log(`Current Debt for the bond is now ${ethers.utils.formatEther(debtAfterDeposit)} LP tokens`);
            console.log(`debtRatio for the bond after deposit is now ${ethers.utils.formatEther(debtRatioAfterDeposit)}`)


            expect(debtRatioAfterDeposit).to.be.gt(initdebtRatio);
            expect(initpayoutFor).to.be.gt(payoutForAfterDeposit);
            expect(debtAfterDeposit).to.be.gt(initialDebtBeforeDeposit);
        })


        it('Should wait 1% of waiting period and then check payout amount, which should have grown', async () => {
            console.log(`Pending payout for User1 straight after deposit is ${ethers.utils.formatEther(initPendingPayout)} CRYSTL`)

            for (i=0; i<462;i++) { //minBlocksBetweenSwaps
                await ethers.provider.send("evm_mine"); //creates a delay of minBlocksBetweenSwaps+1 blocks
                }
            
            userPendingPayoutAfterTime = await customBond.pendingPayoutFor(user1.address);
            debtRatioAfterWP = await customBond.debtRatio();
            debtAfterWP = await customBond.debtRatio();
            payoutForAfterWP = await customBond.payoutFor(initialLPtokenBalance);
            USER1percentVestedAfterWP = await customBond.percentVestedFor(user1.address);
        
            console.log(`Pending payout for User1 462 blocks after deposit is ${ethers.utils.formatEther(userPendingPayoutAfterTime)} CRYSTL`)
            console.log(`debt Ratio after waiting period is ${ethers.utils.formatEther(debtRatioAfterWP)}`);
            console.log(`payout for 1 LP token is ${ethers.utils.formatEther(payoutForAfterWP)}`)
            console.log(`percent vested is ${ethers.utils.formatEther(USER1percentVestedAfterWP)}`);

            expect(userPendingPayoutAfterTime).to.be.gt(initPendingPayout); //will only be true on first deposit?
            expect(debtRatioAfterDeposit).to.be.gt(debtRatioAfterWP);
        })

        it('Should redeem the outstanding payout amount', async () => {
            userPendingPayoutBeforeRedemption = await customBond.pendingPayoutFor(user1.address);
            userCrystlBalanceBeforeRedemption = await crystlToken.balanceOf(user1.address);
            payoutForAfterRedemption = await customBond.payoutFor(initialLPtokenBalance);
            debtAfterRedemption = await customBond.currentDebt();

            console.log(`Pending payout for User1 before redemption is ${ethers.utils.formatEther(userPendingPayoutBeforeRedemption)} CRYSTL`)
            console.log(`CRYSTL balance for User1 before redemption is ${ethers.utils.formatEther(userCrystlBalanceBeforeRedemption)} CRYSTL`)
            console.log(`Debt after redemption is ${ethers.utils.formatEther(debtAfterRedemption)}`)

            await customBond.redeem(user1.address);
            
            userPendingPayoutAfterRedemption = await customBond.pendingPayoutFor(user1.address);
            userCrystlBalanceAfterRedemption = await crystlToken.balanceOf(user1.address);
            console.log(`Pending payout for User1 after redemption is ${ethers.utils.formatEther(userPendingPayoutAfterRedemption)} CRYSTL`)
            console.log(`CRYSTL balance for User1 after redemption is ${ethers.utils.formatEther(userCrystlBalanceAfterRedemption)} CRYSTL`)
            console.log(`Payout for 1 LP token after waiting period and redemption is ${ethers.utils.formatEther(payoutForAfterRedemption)}`)

            expect(initpayoutFor).to.be.gt(payoutForAfterRedemption);
            expect(userCrystlBalanceBeforeRedemption).to.equal(initUserCrystlBalance * 1.1);
            expect(USER1percentVestedAfterWP).to.equal(1);
        })
        
    })
})

