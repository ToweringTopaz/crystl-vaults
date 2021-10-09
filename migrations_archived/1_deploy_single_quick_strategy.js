const StrategyMasterHealerForQuickSwapdQuick = artifacts.require("StrategyMasterHealerForQuickSwapdQuick");
const { quickVaults } = require('../configs/quickVaults');

module.exports = async function (deployer, network) {
    await deployer.deploy(
        StrategyMasterHealerForQuickSwapdQuick,
        quickVaults[0].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...quickVaults[0].strategyConfig // all other contract configuration variables
    )
    const StrategyMasterHealerForQuickSwapdQuickInstance = await StrategyMasterHealerForQuickSwapdQuick.deployed();

    console.table({
        QuickStrategy: StrategyMasterHealerForQuickSwapdQuickInstance.address,
    })
};