const StrategyMiniApe = artifacts.require("StrategyMiniApe");
const { apeSwapVaults } = require('../configs/apeSwapVaults');

module.exports = async function (deployer, network) {
    await deployer.deploy(
        StrategyMiniApe,
        apeSwapVaults[0].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...apeSwapVaults[0].strategyConfig // all other contract configuration variables
    )
    const MaticCrystlStrategyInstance = await StrategyMiniApe.deployed();

    await deployer.deploy(
        StrategyMiniApe,
        apeSwapVaults[1].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...apeSwapVaults[1].strategyConfig // all other contract configuration variables
    )
    const MaticBananaStrategyInstance = await StrategyMiniApe.deployed();

    console.table({
        MaticCrystlStrategy: MaticCrystlStrategyInstance.address,
        MaticBananaStrategy: MaticBananaStrategyInstance.address
    })
};