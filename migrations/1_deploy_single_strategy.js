const StrategyMiniApe = artifacts.require("StrategyMiniApe");
const { apeSwapVaults } = require('../configs/apeSwapVaults');

module.exports = async function (deployer, network) {
    await deployer.deploy(
        StrategyMiniApe,
        apeSwapVaults[7].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...apeSwapVaults[7].strategyConfig // all other contract configuration variables
    )
    const WmaticDaiStrategyStrategyInstance = await StrategyMiniApe.deployed();

    console.table({
        WmaticDaiStrategy: WmaticDaiStrategyStrategyInstance.address,
    })
};