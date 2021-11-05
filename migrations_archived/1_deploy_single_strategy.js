const StrategyMasterHealerForQuick = artifacts.require("StrategyMasterHealerForQuick");
const { quickVaults } = require('../configs/quickVaults');

module.exports = async function (deployer, network) {
    await deployer.deploy(
        StrategyMasterHealerForQuick,
        quickVaults[0].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...quickVaults[0].strategyConfig // all other contract configuration variables
    )
    const StrategyMasterHealerForQuickInstance = await StrategyMasterHealerForQuick.deployed();

    console.table({
        QuickStrategy: StrategyMasterHealerForQuickInstance.address,
    })
};