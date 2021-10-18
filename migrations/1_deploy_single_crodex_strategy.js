const StrategyMasterHealer = artifacts.require("StrategyMasterHealer");
const { crodexVaults } = require('../configs/crodexVaults');

module.exports = async function (deployer, network) {
    await deployer.deploy(
        StrategyMasterHealer,
        crodexVaults[0].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...crodexVaults[0].strategyConfig // all other contract configuration variables
    )
    const WethWbtcStrategyInstance = await StrategyMasterHealer.deployed();

    console.table({
        WbtcWethStrategy: WethWbtcStrategyInstance.address,
    })
};