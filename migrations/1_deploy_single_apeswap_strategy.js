const StrategyMasterHealer = artifacts.require("StrategyMasterHealer");
const { jetswapVaults } = require('../configs/jetswapVaults');

module.exports = async function (deployer, network) {
    await deployer.deploy(
        StrategyMasterHealer,
        jetswapVaults[0].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...jetswapVaults[0].strategyConfig // all other contract configuration variables
    )
    const WethWbtcStrategyInstance = await StrategyMasterHealer.deployed();

    console.table({
        WbtcWethStrategy: WethWbtcStrategyInstance.address,
    })
};