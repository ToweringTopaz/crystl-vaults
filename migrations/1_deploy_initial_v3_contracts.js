const Cavendish = artifacts.require("Cavendish");
const VaultFeeManager = artifacts.require("VaultFeeManager");
const Magnetite = artifacts.require("Magnetite");
const VaultHealer = artifacts.require("VaultHealer");
const StrategyConfig = artifacts.require("StrategyConfig");
const Tactics = artifacts.require("Tactics");
const StrategyQuick = artifacts.require("StrategyQuick");
const Strategy = artifacts.require("Strategy");
const BoostPool = artifacts.require("BoostPool");

module.exports = async function (deployer, network) {
    await deployer.deploy(Cavendish);
	const CavendishInstance = await Cavendish.deployed();
	deployer.link(Cavendish, VaultHealer);
	
    await deployer.deploy(StrategyConfig);
	const StrategyConfigInstance = await StrategyConfig.deployed();
    await deployer.deploy(Tactics);
	const TacticsInstance = await Tactics.deployed();
	
	await deployer.deploy(Magnetite);
	const MagnetiteInstance = await Magnetite.deployed();

	await deployer.deploy(BoostPool);
	const BoostPoolInstance = await BoostPool.deployed();

};
