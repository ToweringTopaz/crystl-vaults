const StrategyMasterHealer = artifacts.require("StrategyMasterHealer");
const { apeSwapVaults } = require('../configs/apeSwapVaults');

module.exports = async function (deployer, network) {
    await deployer.deploy(
        StrategyMasterHealer,
        apeSwapVaults[7].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...apeSwapVaults[7].strategyConfig // all other contract configuration variables
    )
    const WmaticDaiStrategyInstance = await StrategyMasterHealer.deployed();

    console.table({
        WmaticDaiStrategy: WmaticDaiStrategyInstance.address,
    })
};