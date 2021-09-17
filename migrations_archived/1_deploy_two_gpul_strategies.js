const StrategyMasterHealerForReflect = artifacts.require("StrategyMasterHealerForReflect");
const { gpulVaults } = require('../configs/gpulVaults');

module.exports = async function (deployer, network) {
    await deployer.deploy(
        StrategyMasterHealerForReflect,
        gpulVaults[0].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...gpulVaults[0].strategyConfig // all other contract configuration variables
    )
    const MaticGpulStrategyInstance = await StrategyMasterHealerForReflect.deployed();

    await deployer.deploy(
        StrategyMasterHealerForReflect,
        gpulVaults[1].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...gpulVaults[1].strategyConfig // all other contract configuration variables
    )
    const MaticGbntStrategyInstance = await StrategyMasterHealerForReflect.deployed();

    console.table({
        MaticGpulStrategy: MaticGpulStrategyInstance.address,
        MaticGbntStrategy: MaticGbntStrategyInstance.address
    })
};