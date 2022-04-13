import { ethers, network } from "hardhat";
import { task } from "hardhat/config";
import { BigNumber } from "ethers";
import { expect } from "chai";
import { tokens, accounts, lps, routers } from "../configs/addresses";
import { advanceBlock, advanceBlockTo, advanceBlockWithNumber, setBalance, increaseTime, setERC20TokenBalance, getMaticPrice, getTokenPair, getCrystlPrice } from "../test/utils";
const { WMATIC, CRYSTL, DAI } = tokens.polygon;
const { MATIC_CRYSTL_APE_LP } = lps.polygon;
const { APESWAP_ROUTER } = routers.polygon;
const { FEE_ADDRESS, BURN_ADDRESS, ZERO_ADDRESS } = accounts.polygon;
import { IUniRouter02_abi } from '../test/abi_files/IUniRouter02_abi';
import { token_abi } from '../test/abi_files/token_abi';
import { IWETH_abi } from '../test/abi_files/IWETH_abi';
import { Contract, ContractFactory, Signer } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Address } from "cluster";
const { IUniswapV2Pair_abi } = require('../test/abi_files/IUniswapV2Pair_abi.js');


let LPtoken: Contract;
let wmatic_token: Contract;
let crystlToken: Contract;
let crystlTokenTotalSupply: any;
let crystlTokenDecimals: any;

let wmatic: String;
let crystl: String;

let user1: SignerWithAddress, user2: SignerWithAddress, user3: SignerWithAddress, _: SignerWithAddress;

let CustomTreasury: ContractFactory;
let customTreasury: Contract;

let CustomBond: ContractFactory;
let customBond: Contract;

let uniswapRouter: Contract;
let token0: Contract;
let token1: Contract;
let LPtotalSupply:any;


// The time of the current block 24162989 is Jan-25-2022 10:49:26 PM +UTC
// 0.06884 ~ 0.07543 USD (11:00pm : 0.07543 USD)
// $1.56 / MATIC
// 1.56 * 0.641025 = 0.999999 USD (0.641025 MATIC worths 1 USD)

// ------------
// COMMAND-LINE 
// npx ts-node scripts/BondAdjustment.ts <customBond Addr> <customTreasury Addr>
// ------------


async function main() {

    const addrArguments = process.argv;

     // 1 MATIC's value in USD
     let maticInUSD: any;

     // Amount of MATIC that worths 1 USD
     let oneUsdMatic: any;
 
     // Amount of CRYSTL for 1 USD worth of MATIC
     let amountsOut: any;
 
     // 1 USD worth of WMATIC-CRYSTL LP Token
     let oneUsdLP: any;
 
     // Initial Payout Amount of CRYSTL for LP Token from Bond Market
     let initialBondPayout: any;
 
     // Initial Bond Market Discount Rate
     let initialBondMarketDiscountRate: any;
 
     // Ratio of ideal payout & actual payout
     let payoutRatio: any;
 
     // Initial BCV of Bond Market
     let initialBCV: any;
 
     // Target BCV for ideal discount rate
     let targetBCV: any;
 
     // Maximum adjustment Rate for adjusting BCV
     let maxAdjustmentRate: any;
     // Adjustment Rate for adjusting BCV
     let adjustmentRate: any;
 
     // Count of deposit need to get to targetBCV
     let depositCount: number;
 
     // Variables to call setAjustment() for BCV modification
     let _addition: boolean;
     let _increment: number;
     let _target: number;
     let _buffer: number;

     let wmaticAmount:any;
     let crytlAmount:any;
     let LPValue:any;
     let USDWorthLP:any;
     // 1 MATIC's value in USD
     let crystlInUSD:any;
 
     // Amount of CRYSTL that worths 1 USD
     let oneUsdCrystl:any;


    if(addrArguments[2].length != 42 || addrArguments[3].length != 42) {
        throw new Error("Invalide CustomBond or CustomTreasury Address given");
    }
    const customBondAddr = addrArguments[2];
    const customTreasuryAddr = addrArguments[3];

    [user1] = await ethers.getSigners();

    CustomTreasury = await ethers.getContractFactory("CustomTreasury");
    CustomBond = await ethers.getContractFactory("CustomBond");

    customTreasury = await CustomTreasury.attach(customTreasuryAddr);
    customBond = await CustomBond.attach(customBondAddr);

    // LPToken decimals : 18
    LPtoken = await ethers.getContractAt(IUniswapV2Pair_abi, MATIC_CRYSTL_APE_LP);

    LPtotalSupply = await LPtoken.totalSupply();
    LPtotalSupply = ethers.utils.formatEther(LPtotalSupply);

    const TOKEN0ADDRESS = await LPtoken.token0();
    const TOKEN1ADDRESS = await LPtoken.token1();

    let maticPrice = await getMaticPrice();
    let crystlPrice = await getCrystlPrice();

    const pair = await getTokenPair();
    const uniPair = await ethers.getContractAt(IUniswapV2Pair_abi, pair);
    const reserves = await uniPair.getReserves();


    wmaticAmount = ethers.utils.formatEther(reserves.reserve0);
    crytlAmount = ethers.utils.formatEther(reserves.reserve1);

    LPValue = ((wmaticAmount * maticPrice) + (crytlAmount * crystlPrice)) / LPtotalSupply;

    console.log("1 LP Token Value in USD :: ", LPValue);
    console.log("1 USD worth of LP Token :: ", 1 / LPValue);
    console.log("2 USD worth of LP Token :: ", 2 / LPValue);

    maticInUSD = maticPrice;
    crystlInUSD = crystlPrice;
    oneUsdMatic = 1 / maticInUSD;
    oneUsdCrystl = 1 / crystlInUSD;

    uniswapRouter = await ethers.getContractAt(IUniRouter02_abi, APESWAP_ROUTER);

    // fund the treasury with reward token, Crystl
    crystlToken = await ethers.getContractAt(token_abi, CRYSTL);
    // user 1 balance of CRYSTL is 457,342114826036968505

    crystlTokenTotalSupply = await crystlToken.totalSupply(); // 0x0a5c56a51123c165ccffed: 12,525,314,226888042533945325
    crystlTokenDecimals = await crystlToken.decimals(); // 18

    // Create instances of token0 and token1
    token0 = await ethers.getContractAt(token_abi, TOKEN0ADDRESS);
    token1 = await ethers.getContractAt(token_abi, TOKEN1ADDRESS);

    wmatic = token0.address;
    crystl = token1.address;

    // "STEP - 1 : Get the price of MATIC"
    const blockNumber = await ethers.provider.send("eth_blockNumber", []);
    console.log(`BlockNumber :: ${blockNumber}`);

    // "STEP - 3 : Fetch pay out amount of CRYSTL for 1 USD worth of MATIC"
    amountsOut = await uniswapRouter.getAmountsOut(ethers.utils.parseEther(oneUsdMatic.toString()), [wmatic, crystl]);
    amountsOut = amountsOut[1];
    console.log(`1 USD amount of CRYSTL from ApeSwap :: `, ethers.utils.formatEther(amountsOut.toString()));

    // `STEP - 5 : Get the amount of LP token that worths 2 USD`
    // 1 USD Worth of Matic token
    oneUsdLP = 1 / LPValue;
    console.log(`1 USD worth of LP token :: `, oneUsdLP);

    USDWorthLP = 2 / LPValue;
    // `STEP - 6 : Calculate how much crystl token is paid out for 2 USD worth of LP token`
    initialBondPayout = await customBond.payoutFor(ethers.utils.parseEther(USDWorthLP.toString()));
    console.log(`Initial amount of payout for CRYSTL :: `, ethers.utils.formatEther(initialBondPayout.toString()));

    initialBondMarketDiscountRate = (initialBondPayout - (amountsOut * 2)) / (amountsOut * 2) * 100;
    console.log(`Initial bond market discount rate :: `, initialBondMarketDiscountRate);

    // `STEP - 7 : Calculate R(ratio) of ideal payout amount & actual payout amount`
    payoutRatio = initialBondPayout / ((amountsOut * 2) + ((amountsOut * 2) * 0.05));
    console.log(`payoutRatio :: `, payoutRatio);

    // `STEP - 8 : Draw out target BCV by multiplying R`
    const terms = await customBond.terms();
    initialBCV = terms.controlVariable;
    console.log(`Current Bond Market BCV :: `, initialBCV.toNumber());

    targetBCV = initialBCV * payoutRatio;
    console.log(`Target BCV :: `, targetBCV);

    // `STEP - 9 : Calculate how many deposit should happen to get to the targetBCV using maximum rate`
    // 3% is maximum adjustment rate
    maxAdjustmentRate = (initialBCV * 3 / 100) - 1;
    adjustmentRate = maxAdjustmentRate;
    const discrepancy = Math.abs(targetBCV - initialBCV);
    depositCount = discrepancy / adjustmentRate;
    depositCount = Math.floor(depositCount) + 1;
    console.log(`After ${depositCount} deposit, BCV gets adjusted from ${initialBCV} to ${initialBCV - (adjustmentRate * depositCount)}`);

    // `STEP - 10 : Compute market variables to call setAdjustment() for BCV modification`
    _addition = (initialBCV - targetBCV) > 0 ? false : true;
    _increment = adjustmentRate;
    _target = Math.floor(targetBCV);
    _buffer = 0;

    console.log(`----------Arguments for setAdjustment()----------`);
    console.log(`           _addition : ${_addition}`);
    console.log(`           _increment : ${_increment}`);
    console.log(`           _target : ${_target}`);
    console.log(`           _buffer : ${_buffer}`);

    const adjustedBCV = _addition ? Number(initialBCV) + Number(adjustmentRate * depositCount) : Number(initialBCV) - Number(adjustmentRate * depositCount);
    const debtRatio = await customBond.debtRatio() / 1e13;
    const price = debtRatio * adjustedBCV;
    console.log("adjustedBCV :: ", adjustedBCV);
    console.log("debtRatio :: ", debtRatio);
    console.log("Price :: ", price);
    const amount = ethers.utils.parseEther(USDWorthLP.toString());
    console.log("Amount :: ", amount);
    console.log("Amount :: ", Number(amount));

    const payout = Number(amount) / (price) * 1e7;
    const discountRate = (Number(payout) - (amountsOut * 2)) / (amountsOut * 2) * 100;

    console.log("amountsOut :: ", amountsOut);

    console.log("Payout :: ", payout);
    console.log("Estimated DiscountRate :: ", discountRate);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });