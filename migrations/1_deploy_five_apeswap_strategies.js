const StrategyMiniApe = artifacts.require("StrategyMiniApe");
const { apeSwapVaults } = require('../configs/apeSwapVaults');

module.exports = async function (deployer, network) {
    
    await deployer.deploy(
        StrategyMiniApe,
        apeSwapVaults[1].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...apeSwapVaults[1].strategyConfig // all other contract configuration variables
    )
    const WmaticBananaStrategyInstance = await StrategyMiniApe.deployed();

    await deployer.deploy(
        StrategyMiniApe,
        apeSwapVaults[2].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...apeSwapVaults[2].strategyConfig // all other contract configuration variables
    )
    const WmaticBnbStrategyInstance = await StrategyMiniApe.deployed();

    await deployer.deploy(
        StrategyMiniApe,
        apeSwapVaults[3].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...apeSwapVaults[3].strategyConfig // all other contract configuration variables
    )
    const UsdcDaiStrategyInstance = await StrategyMiniApe.deployed();

    await deployer.deploy(
        StrategyMiniApe,
        apeSwapVaults[4].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...apeSwapVaults[4].strategyConfig // all other contract configuration variables
    )
    const WmaticBtcStrategyInstance = await StrategyMiniApe.deployed();

    console.table({
        WmaticBananaStrategy: WmaticBananaStrategyInstance.address,
        WmaticBnbStrategy: WmaticBnbStrategyInstance.address,
        UsdcDaiStrategy: UsdcDaiStrategyInstance.address,
        WmaticBtcStrategy: WmaticBtcStrategyInstance.address
    })
};