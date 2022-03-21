const { tokens, accounts, routers } = require('../configs/addresses.js');
const { ethers } = require('hardhat');
const { FEE_ADDRESS, ZERO_ADDRESS } = accounts.polygon;

const Cavendish = artifacts.require("Cavendish");
const VaultFeeManager = artifacts.require("VaultFeeManager");
const Magnetite = artifacts.require("Magnetite");
const VaultHealer = artifacts.require("VaultHealer");
const StrategyConfig = artifacts.require("StrategyConfig");
const Tactics = artifacts.require("Tactics");
const StrategyQuick = artifacts.require("StrategyQuick");
const Strategy = artifacts.require("Strategy");
const BoostPool = artifacts.require("BoostPool");
const QuartzUniV2Zap = artifacts.require("QuartzUniV2Zap");

withdrawFee = ethers.BigNumber.from(10);
earnFee = ethers.BigNumber.from(500);

let [tacticsA, tacticsB] = await tactics.generateTactics(
	dfynVaults[0]['masterchef'],
	dfynVaults[0]['PID'],
	0, //position of return value in vaultSharesTotal returnData array - have to look at contract and see
	ethers.BigNumber.from("0x70a0823130000000"), //vaultSharesTotal - includes selector and encoded call format
	ethers.BigNumber.from("0xa694fc3a40000000"), //deposit - includes selector and encoded call format
	ethers.BigNumber.from("0x2e1a7d4d40000000"), //withdraw - includes selector and encoded call format
	ethers.BigNumber.from("0x3d18b91200000000"), //harvest - includes selector and encoded call format
	ethers.BigNumber.from("0xe9fad8ee00000000") //emergency withdraw - includes selector and encoded call format
);


DEPLOYMENT_DATA = await strategyConfig.generateConfig(
	tacticsA,
	tacticsB,
	dfynVaults[0]['want'],
	dfynVaults[0]['wantDust'],
	LP_AND_EARN_ROUTER, //note this has to be specified at deployment time
	magnetite.address,
	240, //slippageFactor
	false, //feeOnTransfer
	dfynVaults[0]['earned'],
	dfynVaults[0]['earnedDust'],
);

await vaultHealer.connect(vaultHealerOwnerSigner).createVault(strategyImplementation.address, DEPLOYMENT_DATA);

strat1_pid = await vaultHealer.numVaultsBase();

	console.log("vaultHealer: ", vaultHealer.address);
	console.log("VaultFeeManager: ", vaultFeeManager.address);
	console.log("StrategyConfig: ", strategyConfigInstance.address);
	console.log("Tactics: ", tacticsInstance.address);
	console.log("Strategy: ", strategyImplementation.address);

