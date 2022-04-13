import { BigNumber } from "ethers";
import hre, { network } from "hardhat";
const { ethers } = require("hardhat");
import { ERC20 } from "../typechain";
const { token_abi } = require('../test/abi_files/token_abi');
import { expect } from "chai";
import { tokens, accounts, lps, routers } from "../configs/addresses";
import { resolve } from "path";

import { config as dotenvConfig } from "dotenv";
import { resolveSoa } from "dns";

import fetch from "node-fetch";
import { URL } from "url";
const { WMATIC, CRYSTL, DAI } = tokens.polygon;
const { MATIC_CRYSTL_APE_LP } = lps.polygon;
const { APESWAP_ROUTER } = routers.polygon;
const { FEE_ADDRESS, BURN_ADDRESS, ZERO_ADDRESS } = accounts.polygon;
import { IUniRouter02_abi } from '../test/abi_files/IUniRouter02_abi';
import { IWETH_abi } from '../test/abi_files/IWETH_abi';
import { Contract, ContractFactory, Signer } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Address } from "cluster";
const { IUniswapV2Pair_abi } = require('../test/abi_files/IUniswapV2Pair_abi.js');
const { UniswapV2Factory_abi } = require('../test/abi_files/UniswapV2Factory_abi.js');

const Request = require('request');

dotenvConfig({ path: resolve(__dirname, "../.env") });

const setStorageAt = (address: string, slot: string, val: string) =>
  hre.network.provider.send("hardhat_setStorageAt", [address, slot, val]);

const tokenBalancesSlot = async (token: ERC20) => {
  const val: string = "0x" + "12345".padStart(64, "0");
  const account: string = ethers.constants.AddressZero;

  for (let i = 0; i < 100; i++) {
    let slot = ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [account, i]));
    while (slot.startsWith("0x0")) slot = "0x" + slot.slice(3);

    const prev = await hre.network.provider.send("eth_getStorageAt", [account, slot, "latest"]);
    await setStorageAt(token.address, slot, val);
    const balance = await token.balanceOf(account);
    await setStorageAt(token.address, slot, prev);
    if (balance.eq(ethers.BigNumber.from(val))) {
      return { index: i, isVyper: false };
    }
  }

  for (let i = 0; i < 100; i++) {
    let slot = ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(["uint256", "address"], [i, account]));
    while (slot.startsWith("0x0")) slot = "0x" + slot.slice(3);

    const prev = await hre.network.provider.send("eth_getStorageAt", [account, slot, "latest"]);
    await setStorageAt(token.address, slot, val);
    const balance = await token.balanceOf(account);
    await setStorageAt(token.address, slot, prev);
    if (balance.eq(ethers.BigNumber.from(val))) {
      return { index: i, isVyper: true };
    }
  }
  throw "balances slot not found!";
};

// Source : https://blog.euler.finance/brute-force-storage-layout-discovery-in-erc20-contracts-with-hardhat-7ff9342143ed
export async function setTokenBalanceInStorage(token: ERC20, account: string, amount: string) {
  const balancesSlot = await tokenBalancesSlot(token);
  if (balancesSlot.isVyper) {
    return setStorageAt(
      token.address,
      ethers.utils.keccak256(
        ethers.utils.defaultAbiCoder.encode(["uint256", "address"], [balancesSlot.index, account]),
      ),
      "0x" +
      ethers.utils
        .parseUnits(amount, await token.decimals())
        .toHexString()
        .slice(2)
        .padStart(64, "0"),
    );
  } else {
    return setStorageAt(
      token.address,
      ethers.utils.hexStripZeros(
        ethers.utils.keccak256(
          ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [account, balancesSlot.index]),
        ),
      ),
      "0x" +
      ethers.utils
        .parseUnits(amount, await token.decimals())
        .toHexString()
        .slice(2)
        .padStart(64, "0"),
    );
  }
}

export const advanceBlock = async () => {
  return await ethers.provider.send("evm_mine", [])
}

export const advanceBlockTo = async (blockNumber: number) => {
  for (let i = await ethers.provider.getBlockNumber(); i < blockNumber; i++) {
    await advanceBlock()
  }
}

export const advanceBlockWithNumber = async (blockNumber: number) => {
  for (let i = 0; i < blockNumber; i++)
    await advanceBlock()
}

export const setBalance = async (addr: string, balance: string) => {
  await network.provider.send("hardhat_setBalance", [
    addr,
    balance,
  ]);
}

export const increaseTime = async (time: number) => {
  await network.provider.send("evm_increaseTime", [time]);
}

export const toBytes32 = (bn: BigNumber) => {
  return ethers.utils.hexlify(ethers.utils.zeroPad(bn.toHexString(), 32));
};

export const setERC20TokenBalance = async (slot: number = 0x1, tokenAddr: string, userAddr: string, balance: BigNumber) => {
  // 
  const token = new ethers.Contract(tokenAddr, token_abi, ethers.provider);
  const index = ethers.utils.solidityKeccak256(
    ["uint256", "uint256"],
    [userAddr, slot]
  );

  await setStorageAtToken(
    tokenAddr,
    index.toString(),
    toBytes32(balance).toString()
  );

}

export const setStorageAtToken = async (address: string, index: number, value: string) => {
  await ethers.provider.send("hardhat_setStorageAt", [address, index, value]);
  await ethers.provider.send("evm_mine", []); // Just mines to the next block
};

export const getMaticPrice = async () => {
  const response = await fetch('https://api.coingecko.com/api/v3/simple/token_price/polygon-pos?contract_addresses=0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270&vs_currencies=usd');
  if (response.status === 200) {
    const res = await response.json();
    return res["0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270"].usd;
  }
  else
    throw new Error("Coingecko API Request went wrong. Cannot fetch MATIC Price with given url")

}

export const getCrystlPrice = async () => {
  const response = await fetch('https://api.coingecko.com/api/v3/simple/token_price/polygon-pos?contract_addresses=0x76bF0C28e604CC3fE9967c83b3C3F31c213cfE64&vs_currencies=usd');
  if (response.status === 200) {
    const res = await response.json();
    return res["0x76bf0c28e604cc3fe9967c83b3c3f31c213cfe64"].usd;
  }
  else
    throw new Error("Coingecko API Request went wrong. Cannot fetch MATIC Price with given url")
}

// Should return params to call setAdjustment()
// _addition
// _increment
// _target
// _buffer
export const getAdjustmentValue = async (customBond: any, customTreasury: any) => {
  let LPtoken: Contract;
  let crystlToken: Contract;
  let crystlTokenTotalSupply: any;
  let crystlTokenDecimals: any;

  let wmatic: String;
  let crystl: String;

  let user1: SignerWithAddress, user2: SignerWithAddress, user3: SignerWithAddress, _: SignerWithAddress;

  let CustomTreasury: ContractFactory;

  let CustomBond: ContractFactory;

  let uniswapRouter: Contract;
  let token0: Contract;
  let token1: Contract;
  let LPtotalSupply: any;
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

  let wmaticAmount: any;
  let crytlAmount: any;
  let LPValue: any;
  let USDWorthLP: any;
  // 1 MATIC's value in USD
  let crystlInUSD: any;

  // Amount of CRYSTL that worths 1 USD
  let oneUsdCrystl: any;

  const customBondAddr = customBond;
  const customTreasuryAddr = customTreasury;

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


  // "STEP - 3 : Fetch pay out amount of CRYSTL for 1 USD worth of MATIC"
  amountsOut = await uniswapRouter.getAmountsOut(ethers.utils.parseEther(oneUsdMatic.toString()), [wmatic, crystl]);
  amountsOut = amountsOut[1];

  // 1 USD Worth of Matic token
  oneUsdLP = 1 / LPValue;

  USDWorthLP = 2 / LPValue;
  initialBondPayout = await customBond.payoutFor(ethers.utils.parseEther(USDWorthLP.toString()));

  initialBondMarketDiscountRate = (initialBondPayout - (amountsOut * 2)) / (amountsOut * 2) * 100;
  console.log('initialBondMarketDiscountRate : ', initialBondMarketDiscountRate);
  // `STEP - 7 : Calculate R(ratio) of ideal payout amount & actual payout amount`
  payoutRatio = initialBondPayout / ((amountsOut * 2) + ((amountsOut * 2) * 0.05));

  // `STEP - 8 : Draw out target BCV by multiplying R`
  const terms = await customBond.terms();
  initialBCV = terms.controlVariable;

  targetBCV = initialBCV * payoutRatio;

  // `STEP - 9 : Calculate how many deposit should happen to get to the targetBCV using maximum rate`
  // 3% is maximum adjustment rate
  maxAdjustmentRate = (initialBCV * 3 / 100) - 1;
  adjustmentRate = Math.floor(maxAdjustmentRate);
  const discrepancy = Math.abs(targetBCV - initialBCV);
  depositCount = discrepancy / adjustmentRate;
  depositCount = Math.floor(depositCount) + 1;

  // `STEP - 10 : Compute market variables to call setAdjustment() for BCV modification`
  _addition = (initialBCV - targetBCV) > 0 ? false : true;
  _increment = adjustmentRate;
  _target = Math.floor(targetBCV);
  _buffer = 0;

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

  return {
    _addition,
    _increment,
    _target,
    _buffer
  }
}

export const getDiscountRate = async (customBond: any, customTreasury: any) => {
  let LPtoken: Contract;
  let crystlToken: Contract;
  let crystlTokenTotalSupply: any;
  let crystlTokenDecimals: any;

  let wmatic: String;
  let crystl: String;

  let user1: SignerWithAddress, user2: SignerWithAddress, user3: SignerWithAddress, _: SignerWithAddress;

  let CustomTreasury: ContractFactory;

  let CustomBond: ContractFactory;

  let uniswapRouter: Contract;
  let token0: Contract;
  let token1: Contract;
  let LPtotalSupply: any;
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

  let wmaticAmount: any;
  let crytlAmount: any;
  let LPValue: any;
  let USDWorthLP: any;
  // 1 MATIC's value in USD
  let crystlInUSD: any;

  // Amount of CRYSTL that worths 1 USD
  let oneUsdCrystl: any;

  const customBondAddr = customBond;
  const customTreasuryAddr = customTreasury;

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


  // "STEP - 3 : Fetch pay out amount of CRYSTL for 1 USD worth of MATIC"
  amountsOut = await uniswapRouter.getAmountsOut(ethers.utils.parseEther(oneUsdMatic.toString()), [wmatic, crystl]);
  amountsOut = amountsOut[1];

  // 1 USD Worth of Matic token
  oneUsdLP = 1 / LPValue;

  USDWorthLP = 2 / LPValue;
  initialBondPayout = await customBond.payoutFor(ethers.utils.parseEther(USDWorthLP.toString()));

  initialBondMarketDiscountRate = (initialBondPayout - (amountsOut * 2)) / (amountsOut * 2) * 100;

  return initialBondMarketDiscountRate;
}

export const getTokenPair = async () => {
  // 0xCf083Be4164828f00cAE704EC15a36D711491284 : ApeSwap Factory
  const factory = await ethers.getContractAt(UniswapV2Factory_abi, "0xCf083Be4164828f00cAE704EC15a36D711491284");
  const pairAddr = await factory.getPair(WMATIC, CRYSTL);
  return pairAddr;
}