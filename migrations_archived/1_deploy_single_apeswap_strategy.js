const StrategyMiniApe = artifacts.require("StrategyMiniApe");
const { apeSwapVaults } = require('../configs/apeSwapVaults');

module.exports = async function (deployer, network) {
    await deployer.deploy(
        StrategyMiniApe,
        apeSwapVaults[4].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...apeSwapVaults[4].strategyConfig // all other contract configuration variables
    )
    const WmaticWbtcStrategyInstance = await StrategyMiniApe.deployed();

    console.table({
        WmaticWbtcStrategy: WmaticWbtcStrategyInstance.address,
    })
};