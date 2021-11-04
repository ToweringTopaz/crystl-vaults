const StrategyMasterHealer = artifacts.require("StrategyMasterHealer");
const { cronaswapVaults } = require('../configs/cronaswapVaults');

module.exports = async function (deployer, network) {
    await deployer.deploy(
        StrategyMasterHealer,
        cronaswapVaults[1].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...cronaswapVaults[1].strategyConfig // all other contract configuration variables
    )
    const WcroUsdcStrategyInstance = await StrategyMasterHealer.deployed();

    console.table({
        WcroUsdcStrategy: WcroUsdcStrategyInstance.address,
    })
};