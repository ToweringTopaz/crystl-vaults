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

module.exports = async function (deployer, network, accounts) {
	await deployer.deploy(VaultHealer)
	vaultHealer = await VaultHealer.deployed();

    // await deployer.deploy(StrategyConfig, );
	// const strategyConfigInstance = await StrategyConfig.deployed();

    // await deployer.deploy(Tactics);
	// const tacticsInstance = await Tactics.deployed();
    
	// await deployer.deploy(Strategy, vaultHealer.address); //vaultHealer.address
	// const strategyImplementation = await Strategy.deployed();

	// // await deployer.deploy(BoostPool, vaultHealer.address);
	// // const boostPoolImplementation = await BoostPool.deployed();

	console.log("vaultHealer: ", vaultHealer.address);
	// console.log("VaultFeeManager: ", vaultFeeManager.address);
	// console.log("StrategyConfig: ", strategyConfigInstance.address);
	// console.log("Tactics: ", tacticsInstance.address);
	// console.log("Strategy: ", strategyImplementation.address);
};
