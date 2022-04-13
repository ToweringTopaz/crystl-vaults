import { ethers, network } from "hardhat";
import { BigNumber } from "ethers";
import { expect } from "chai";
import { tokens, accounts, lps, routers } from "../configs/addresses";
import { advanceBlock, advanceBlockTo, advanceBlockWithNumber, setBalance, increaseTime, setERC20TokenBalance, getMaticPrice, getTokenPair, getCrystlPrice } from "./utils";
const { WMATIC, CRYSTL, DAI } = tokens.polygon;
const { MATIC_CRYSTL_APE_LP } = lps.polygon;
const { APESWAP_ROUTER } = routers.polygon;
const { FEE_ADDRESS, BURN_ADDRESS, ZERO_ADDRESS } = accounts.polygon;
import { IUniRouter02_abi } from './abi_files/IUniRouter02_abi';
import { token_abi } from './abi_files/token_abi';
import { IWETH_abi } from './abi_files/IWETH_abi';
import { Contract, ContractFactory, Signer } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Address } from "cluster";
const { IUniswapV2Pair_abi } = require('./abi_files/IUniswapV2Pair_abi.js');


describe(`Bond Market price adjustment`, () => {
    let LPtoken:Contract;
    let wmatic_token:Contract;
    let crystlToken:Contract;
    let crystlTokenTotalSupply: any;
    let crystlTokenDecimals: any;

    let wmatic:String;
    let crystl:String;

    let user1:SignerWithAddress, user2:SignerWithAddress, user3:SignerWithAddress, _:SignerWithAddress;
        
    let CustomTreasury:ContractFactory;
    let customTreasury:Contract;

    let CustomBond:ContractFactory;
    let customBond:Contract;

    let uniswapRouter:Contract;
    let token0:Contract;
    let token1:Contract;

    let vestingTerm = 38000 * 7; // Polygon - average 38000 in a day * 7; Ethereum - 46200: 7 days
    let minimumPrice = 10000;
    let initialCV = 250000;
    let maxPayout = 5000;
    let maxDebt = "100000000000000000000000"; // 1e23
    // let maxDebt = "1000000000000000000000000"; // 1e24
    let initialDebt = "650000000000000000000"; // 65e19
    // let initialDebt = "9000000000000000000000000"; // 9e13
    let maxInt = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";

    before(async () => {
        [user1, user2, user3, _] = await ethers.getSigners();

        CustomTreasury = await ethers.getContractFactory("CustomTreasury");
        CustomBond = await ethers.getContractFactory("CustomBond");
    });

    beforeEach(async () => {
        customTreasury = await CustomTreasury.deploy(
            CRYSTL,         //address _payoutToken,  todo - what should this be? we bond crystl and pay out in?
            user1.address,  //address _initialOwner
        );
        customBond = await CustomBond.deploy(        
            customTreasury.address, //address _customTreasury, 
            MATIC_CRYSTL_APE_LP,    //address _principalToken, CRYSTL-CRO LP
            user1.address,          //address _initialOwner
        );
        // user1's balance of principal token is 457,342114826036968505
        
        await customTreasury.toggleBondContract(customBond.address);
        
        await customBond.setBondTerms(0, vestingTerm); //PARAMETER = { 0: VESTING, 1: PAYOUT, 3: DEBT }

        await customBond.initializeBond(
            initialCV,                    //uint _controlVariable, 
            vestingTerm,                  //uint _vestingTerm, 7 days
            minimumPrice,                 //1351351, uint _minimumPrice,
            maxPayout,                    //uint _maxPayout, 100e9
            maxDebt,                      //uint _maxDebt, 
            initialDebt,                  //uint _initialDebt
        );

        // LPToken decimals : 18
        LPtoken = await ethers.getContractAt(IUniswapV2Pair_abi, MATIC_CRYSTL_APE_LP);

        await LPtoken.connect(user1).approve(customBond.address, maxInt);
        await LPtoken.connect(user2).approve(customBond.address, maxInt);

        const TOKEN0ADDRESS = await LPtoken.token0();
        const TOKEN1ADDRESS = await LPtoken.token1();
        // console.log("TOKEN0ADDRESS :: ", TOKEN0ADDRESS);
        // console.log("TOKEN1ADDRESS :: ", TOKEN1ADDRESS);

        uniswapRouter = await ethers.getContractAt(IUniRouter02_abi, APESWAP_ROUTER);
        
        // set MATIC balance (10000 MATIC)
        await setBalance(user1.address, "0x21E19E0C9BAB2400000");
        // set MATIC balance (10000000 MATIC)
        await setBalance(user2.address, "0x84595161401484A000000");

        // fund the treasury with reward token, Crystl
        crystlToken = await ethers.getContractAt(token_abi, CRYSTL);
        // user 1 balance of CRYSTL is 457,342114826036968505

        crystlTokenTotalSupply = await crystlToken.totalSupply(); // 0x0a5c56a51123c165ccffed: 12,525,314,226888042533945325
        crystlTokenDecimals = await crystlToken.decimals(); // 18

        // Create instances of token0 and token1
        token0 = await ethers.getContractAt(token_abi, TOKEN0ADDRESS);
        token1 = await ethers.getContractAt(token_abi, TOKEN1ADDRESS);
        
        // user1 approves token to add liquidity to get LP tokens
        var token0BalanceUser1 = await token0.balanceOf(user1.address);
        await token0.approve(uniswapRouter.address, maxInt);
        
        var token1BalanceUser1 = await token1.balanceOf(user1.address);
        await token1.approve(uniswapRouter.address, maxInt);

        wmatic = token0.address;
        crystl = token1.address;
    });

    // The time of the current block 24162989 is Jan-25-2022 10:49:26 PM +UTC
    // 0.06884 ~ 0.07543 USD (11:00pm : 0.07543 USD)
    // $1.56 / MATIC
    // 1.56 * 0.641025 = 0.999999 USD (0.641025 MATIC worths 1 USD)

    describe(`Bond Market Price Adjustment Analysis`, async () => {
        // 1 MATIC's value in USD
        let maticInUSD:any;

        // 1 MATIC's value in USD
        let crystlInUSD:any;

        // Amount of MATIC that worths 1 USD
        let oneUsdMatic:any;

        // Amount of CRYSTL that worths 1 USD
        let oneUsdCrystl:any;

        // Amount of CRYSTL for 1 USD worth of MATIC
        let amountsOut:any;

        // Amount of LP token after providing 2 USD worth of liquidity
        let lpBalance:any;

        // 1 USD worth of WMATIC-CRYSTL LP Token
        let oneUsdLP:any;

        // Initial Payout Amount of CRYSTL for LP Token from Bond Market
        let initialBondPayout:any;

        // Adjusted Payout Amount of CRYSTL for LP Token from Bond Market
        let adjustedBondPayout:any;

        // Initial Bond Market Discount Rate
        let initialBondMarketDiscountRate:any;

        // Adjusted Bond Market Discount Rate
        let adjustedBondMarketDiscountRate:any;

        // Ratio of ideal payout & actual payout
        let payoutRatio:any;

        // Initial BCV of Bond Market
        let initialBCV:any;

        // Target BCV for ideal discount rate
        let targetBCV:any;

        // Maximum adjustment Rate for adjusting BCV
        let maxAdjustmentRate:any;
        // Adjustment Rate for adjusting BCV
        let adjustmentRate:any;

        // Count of deposit need to get to targetBCV
        let depositCount:number;

        // Variables to call setAjustment() for BCV modification
        let _addition:boolean;
        let _increment:number;
        let _target:number;
        let _buffer:number;

        let crytlAmount:any;
        let wmaticAmount:any;
        let LPtotalSupply:any;
        let LPValue:any;
        let USDWorthLP:any;
        it("STEP - 1 : Get the price of MATIC", async () => {
            let price = await getMaticPrice();
            let crystlPrice = await getCrystlPrice();

            const pair = await getTokenPair();
            const uniPair = await ethers.getContractAt(IUniswapV2Pair_abi, pair);
            const reserves = await uniPair.getReserves();
            wmaticAmount = ethers.utils.formatEther(reserves.reserve0);
            crytlAmount = ethers.utils.formatEther(reserves.reserve1);

            console.log("       Amount of Tokens in Reserve 0 :: ", ethers.utils.formatEther(reserves.reserve0));
            console.log("       Amount of Tokens in Reserve 1 :: ", ethers.utils.formatEther(reserves.reserve1));

            console.log("       Value of Reserves 0 (WMATIC):: ", wmaticAmount * price);
            console.log("       Value of Reserves 1 (WMATIC):: ", crytlAmount * crystlPrice);

            console.log("       GetTokenPair :: ", await getTokenPair()); // 0xB8e54c9Ea1616beEBe11505a419DD8dF1000E02a
            console.log("       WMATIC Balance :: ", await token0.balanceOf(pair));
            console.log("       CRYSTL Balance :: ", await token1.balanceOf(pair));
            LPtotalSupply = await LPtoken.totalSupply();
            console.log("       LPtotalSupply :: ", LPtotalSupply);
            LPtotalSupply = ethers.utils.formatEther(LPtotalSupply);
            LPValue = ((wmaticAmount * price) + (crytlAmount * crystlPrice)) / LPtotalSupply;
            console.log("       1 LP Token Value in USD :: ", LPValue);
            console.log("       1 USD worth of LP Token :: ", 1 / LPValue);
            console.log("       2 USD worth of LP Token :: ", 2 / LPValue);

            const blockNumber = await ethers.provider.send("eth_blockNumber", []);
            console.log(`       BlockNumber :: ${blockNumber}`);
            //console.log(await getMaticPrice());

            //console.log(wow["0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270"].usd)
            // maticInUSD = 1.56; // 1 MATIC price in USD
            maticInUSD = price;
            crystlInUSD = crystlPrice;
            console.log(`       Price of MATIC in USD :: `, maticInUSD);
            console.log(`       Price of CRYSTL in USD :: `, crystlInUSD);
        });

        it("STEP - 2 : Calculate 1 USD worth of MATIC", async () => {
            oneUsdMatic = 1 / maticInUSD;
            oneUsdCrystl = 1 / crystlInUSD;

            console.log(`       1 USD amount of MATIC :: `, oneUsdMatic);
            console.log(`       1 USD amount of CRYSTL :: `, oneUsdCrystl);
        });

        it("STEP - 3 : Fetch pay out amount of CRYSTL for 1 USD worth of MATIC", async () => {
            amountsOut = await uniswapRouter.getAmountsOut(ethers.utils.parseEther(oneUsdMatic.toString()), [wmatic, crystl]);
            amountsOut = amountsOut[1];
            console.log(`       1 USD amount of CRYSTL from ApeSwap :: `, ethers.utils.formatEther(amountsOut.toString()));
        });

        it(`STEP - 4 : Get the amount of LP token that worths 2 USD`, async () => {
            // 1 USD Worth of Matic token
            // oneUsdLP = lpBalance / 2;
            oneUsdLP = 1 / LPValue;

            console.log(`       1 USD worth of LP token :: `, oneUsdLP);
        });

        it(`STEP - 5 : Calculate how much crystl token is paid out for 2 USD worth of LP token`, async () => {
            USDWorthLP = 2 / LPValue;

            initialBondPayout = await customBond.payoutFor(ethers.utils.parseEther(USDWorthLP.toString()));
            console.log(`       Initial amount of payout for CRYSTL :: `, ethers.utils.formatEther(initialBondPayout.toString()));

            initialBondMarketDiscountRate = (initialBondPayout - (amountsOut * 2)) / (amountsOut * 2) * 100;

            console.log(`       Initial bond market discount rate :: `, initialBondMarketDiscountRate);
        });

        it(`STEP - 6 : Calculate R(ratio) of ideal payout amount & actual payout amount`, async () => {
            payoutRatio = initialBondPayout / ((amountsOut * 2) + ((amountsOut * 2) * 0.05));
            console.log(`       payoutRatio :: `, payoutRatio);
        });

        it(`STEP - 7 : Draw out target BCV by multiplying R`, async () => {
            const terms = await customBond.terms();
            initialBCV = terms.controlVariable;
            console.log(`       Current Bond Market BCV :: `, initialBCV.toNumber());

            targetBCV = initialBCV * payoutRatio;
            console.log(`       Target BCV :: `, targetBCV);
        });

        it(`STEP - 8 : Calculate how many deposit should happen to get to the targetBCV using maximum rate`, async () => {
            // 3% is maximum adjustment rate
            maxAdjustmentRate = (initialBCV * 3 / 100) - 1;
            adjustmentRate = maxAdjustmentRate;
            const discrepancy = Math.abs(targetBCV - initialBCV);
            depositCount = discrepancy / adjustmentRate;
            depositCount = Math.floor(depositCount) + 1;
            console.log(`       After ${depositCount} deposit, BCV gets adjusted from ${initialBCV} to ${initialBCV - (adjustmentRate * depositCount)}`);
        });

        it(`STEP - 9 : Compute market variables to call setAdjustment() for BCV modification`, async () => {
            _addition = (initialBCV - targetBCV) > 0 ? false : true;
            _increment = adjustmentRate;
            _target = Math.floor(targetBCV);
            _buffer = 0;

            console.log(`       Arguments for setAdjustment()`);
            console.log(`       _addition : ${_addition}`);
            console.log(`       _increment : ${_increment}`);
            console.log(`       _target : ${_target}`);
            console.log(`       _buffer : ${_buffer}`);
        });

        it(`STEP - 10 : Call setAdjustment() to adjust BCV`, async () => {
            await customBond.connect(user1).setAdjustment(_addition, _increment, _target, _buffer);

            const adjustment = await customBond.adjustment();

            expect(adjustment.add).to.equal(_addition);
            expect(adjustment.rate).to.equal(_increment);
            expect(adjustment.target).to.equal(_target);
            expect(adjustment.buffer).to.equal(_buffer);
        });

        it(`STEP - 11 : Estimate discount rate`, async () => {
            const adjustedBCV = _addition ? Number(initialBCV) + Number(adjustmentRate * depositCount) : Number(initialBCV) - Number(adjustmentRate * depositCount);
            const debtRatio = await customBond.debtRatio() / 1e13;
            const price = debtRatio * adjustedBCV;
            console.log("       adjustedBCV :: ", adjustedBCV);
            console.log("       debtRatio :: ", debtRatio);
            console.log("       Price :: ", price);
            const amount = ethers.utils.parseEther(USDWorthLP.toString());
            console.log("       Amount :: ", amount);
            console.log("       Amount :: ", Number(amount));

            const payout = Number(amount) / (price) * 1e7;
            const discountRate = (Number(payout) - (amountsOut * 2)) / (amountsOut * 2) * 100;

            console.log("       amountsOut :: ", amountsOut);

            console.log("       Payout :: ", payout);
            console.log("       Estimated DiscountRate :: ", discountRate);  // 1222007,7423726789000
                                                                    // 1376972
                                                                    // 2.149420029732434000
        });

        it(`FINAL :: Verification : Call deposit(), check if BCV reached target BCV & get adjusted discount rate`, async () => {
            await setERC20TokenBalance(1, CRYSTL, customTreasury.address, ethers.utils.parseEther("100000"));
            await setERC20TokenBalance(1, MATIC_CRYSTL_APE_LP, user1.address, ethers.utils.parseEther("7"));

            await customBond.connect(user1).setAdjustment(_addition, _increment, _target, _buffer);

            for(let i = 0; i < depositCount; i++) {
                const actualTrueBondPrice = await customBond.trueBondPrice();

                await customBond
                    .connect(user1)
                    .deposit(ethers.utils.parseEther("0.1"), Number(actualTrueBondPrice) + 1, user1.address);
            }
            const terms = await customBond.terms();
            const adjustedBCV = terms.controlVariable;
            expect(Number(adjustedBCV)).to.be.lessThanOrEqual(_target);

            // adjustedBondPayout = await customBond.payoutFor(lpBalance);
            adjustedBondPayout = await customBond.payoutFor(ethers.utils.parseEther(USDWorthLP.toString()));

            // adjustedBondMarketDiscountRate = (adjustedBondPayout - (amountsOut * 2)) / amountsOut * 100;
            adjustedBondMarketDiscountRate = (adjustedBondPayout - (amountsOut * 2)) / (amountsOut * 2) * 100;

            console.log(`       Adjusted bond market discount rate :: `, adjustedBondMarketDiscountRate);
        });
    });

});
