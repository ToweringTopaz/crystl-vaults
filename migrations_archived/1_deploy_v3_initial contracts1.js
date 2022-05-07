const { ethers } = require('hardhat');

const VaultHealer = artifacts.require("VaultHealer");
const StrategyQuick = artifacts.require("StrategyQuick");
const Strategy = artifacts.require("Strategy");
const BoostPool = artifacts.require("BoostPool");

withdrawFee = ethers.BigNumber.from(10);
earnFee = ethers.BigNumber.from(500);

module.exports = async function (deployer) {
	await deployer.deploy(VaultHealer)
	vaultHealer = await VaultHealer.deployed();
    
	await deployer.deploy(Strategy, vaultHealer.address);
	const strategyImplementation = await Strategy.deployed();

	await deployer.deploy(StrategyQuick, vaultHealer.address); 
	const strategyQuickImplementation = await StrategyQuick.deployed();

	await deployer.deploy(BoostPool, vaultHealer.address);
	const boostPoolImplementation = await BoostPool.deployed();

	console.log("vaultHealer: ", vaultHealer.address);
	console.log("Strategy: ", strategyImplementation.address);
	console.log("StrategyQuick: ", strategyQuickImplementation.address);
	console.log("BoostPool: ", boostPoolImplementation.address);
};
