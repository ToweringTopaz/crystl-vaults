const StrategyMasterHealer = artifacts.require("StrategyMasterHealer");
const { gpulVaults } = require('../configs/gpulVaults');

module.exports = async function (deployer, network) {
    await deployer.deploy(
        StrategyMasterHealer,
        gpulVaults[0].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...gpulVaults[0].strategyConfig // all other contract configuration variables
    )
    const StrategyMasterHealerInstance = await StrategyMasterHealer.deployed();

    console.table({
        GammaPolyPulsarStrategy: StrategyMasterHealerInstance.address,
    })
};