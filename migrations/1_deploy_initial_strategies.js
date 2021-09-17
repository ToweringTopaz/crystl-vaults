const StrategyMasterHealer = artifacts.require("StrategyMasterHealer");
const StrategyMasterHealerForReflect = artifacts.require("StrategyMasterHealerForReflect");
const StrategyMasterHealerForDoubleReflect = artifacts.require("StrategyMasterHealerForDoubleReflect");
const StrategyMasterHealerForQuick = artifacts.require("StrategyMasterHealerForQuick");
const { takoDefiVaults } = require('../configs/takoDefiVaults');
const { quickVaults } = require('../configs/quickVaults');
const { gpulVaults } = require('../configs/gpulVaults');

module.exports = async function (deployer, network) {
    await deployer.deploy(
        StrategyMasterHealer,
        takoDefiVaults[0].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...takoDefiVaults[0].strategyConfig // all other contract configuration variables
    )
    const MaticCrystalStrategyInstance = await StrategyMasterHealer.deployed();

    await deployer.deploy(
        StrategyMasterHealer,
        takoDefiVaults[1].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...takoDefiVaults[1].strategyConfig // all other contract configuration variables
    )
    const MaticTakoStrategyInstance = await StrategyMasterHealer.deployed();

    await deployer.deploy(
        StrategyMasterHealerForReflect,
        gpulVaults[0].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...gpulVaults[0].strategyConfig // all other contract configuration variables
    )
    const MaticGpulStrategyInstance = await StrategyMasterHealerForReflect.deployed();

    await deployer.deploy(
        StrategyMasterHealerForDoubleReflect,
        gpulVaults[1].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...gpulVaults[1].strategyConfig // all other contract configuration variables
    )
    const MaticGbntStrategyInstance = await StrategyMasterHealerForDoubleReflect.deployed();

    await deployer.deploy(
        StrategyMasterHealerForQuick,
        quickVaults[0].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...quickVaults[0].strategyConfig // all other contract configuration variables
    )
    const StrategyMasterHealerForQuickInstance = await StrategyMasterHealerForQuick.deployed();

    console.table({
        MaticCrystalStrategy: MaticCrystalStrategyInstance.address,
        MaticTakoStrategy: MaticTakoStrategyInstance.address,
        MaticGpulStrategy: MaticGpulStrategyInstance.address,
        MaticGbntStrategy: MaticGbntStrategyInstance.address,
        QuickStrategy: StrategyMasterHealerForQuickInstance.address,
    });
};
