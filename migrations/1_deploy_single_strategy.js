const StrategyMasterHealer = artifacts.require("StrategyMasterHealer");
const { barbershopVaults } = require('../configs/barbershopVaults');

module.exports = async function (deployer, network) {
    await deployer.deploy(
        StrategyMasterHealer,
        barbershopVaults[0].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...barbershopVaults[0].strategyConfig // all other contract configuration variables
    )
    const strategyMasterHealer = await StrategyMasterHealer.deployed();

    console.table({
        BarbershopStrategy: strategyMasterHealer.address,
    })
};