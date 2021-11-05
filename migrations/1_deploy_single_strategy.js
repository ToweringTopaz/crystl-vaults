const StrategyMasterHealer = artifacts.require("StrategyMasterHealer");
const { cronaswapVaults } = require('../configs/cronaswapVaults');

module.exports = async function (deployer, network) {
    await deployer.deploy(
        StrategyMasterHealer,
        cronaswapVaults[0].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...cronaswapVaults[0].strategyConfig // all other contract configuration variables
    )
    const WcroCronaStrategyInstance = await StrategyMasterHealer.deployed();

    console.table({
        WcroCronaStrategy: WcroCronaStrategyInstance.address,
    })
};