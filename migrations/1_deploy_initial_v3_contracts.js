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
withdrawFee = ethers.BigNumber.from(10);
earnFee = ethers.BigNumber.from(500);

module.exports = async function (deployer, network, accounts) {
	console.log(accounts[0]);
	await deployer.deploy(Magnetite);
	const MagnetiteInstance = await Magnetite.deployed();
	
	await deployer.deploy(Cavendish);
	const CavendishInstance = await Cavendish.deployed();

	// const CavendishInstance = await Cavendish.at('0xb2684d1c90ABCE90Fac79c54ac5d38081896E490');
	// await deployer.link(CavendishInstance, VaultHealer);

	await deployer.link(Cavendish, VaultHealer);

	await deployer.deploy(VaultHealer, "", ZERO_ADDRESS, accounts[0])
	vaultHealer = await VaultHealer.deployed();

	await deployer.deploy(VaultFeeManager, 
		vaultHealer.address, 
		FEE_ADDRESS, 
		withdrawFee, 
		[ FEE_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS ], 
		[earnFee, 0, 0])
	vaultFeeManager = await VaultFeeManager.deployed();

	await deployer.deploy(QuartzUniV2Zap, await vaultHealer.zap());
	const quartzUniV2Zap = await QuartzUniV2Zap.deployed();

    await deployer.deploy(StrategyConfig);
	const StrategyConfigInstance = await StrategyConfig.deployed();

    await deployer.deploy(Tactics);
	const TacticsInstance = await Tactics.deployed();
    
	await deployer.deploy(Strategy);
	const strategyImplementation = await Strategy.deployed();

	await deployer.deploy(BoostPool, vaultHealer.address);
	const boostPoolImplementation = await BoostPool.deployed();

};
