const StrategyMiniApe = artifacts.require("StrategyMiniApe");
const { apeSwapVaults } = require('../configs/apeSwapVaults');

module.exports = async function (deployer, network) {
    await deployer.deploy(
        StrategyMiniApe,
        apeSwapVaults[5].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...apeSwapVaults[5].strategyConfig // all other contract configuration variables
    )
    const WmaticWethStrategyInstance = await StrategyMiniApe.deployed();

    await deployer.deploy(
        StrategyMiniApe,
        apeSwapVaults[6].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...apeSwapVaults[6].strategyConfig // all other contract configuration variables
    )
    const WmaticUsdtStrategyInstance = await StrategyMiniApe.deployed();

    console.table({
        WmaticWethStrategy: WmaticWethStrategyInstance.address,
        WmaticUsdtStrategy: WmaticUsdtStrategyInstance.address
    })
};