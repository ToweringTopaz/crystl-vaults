const StrategyMasterHealer = artifacts.require("StrategyMasterHealer");
const { takoDefiVaults } = require('../configs/takoDefiVaults');

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
        StrategyMasterHealer,
        takoDefiVaults[2].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...takoDefiVaults[2].strategyConfig // all other contract configuration variables
    )
    const MaticInkuStrategyInstance = await StrategyMasterHealer.deployed();

    await deployer.deploy(
        StrategyMasterHealer,
        takoDefiVaults[3].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...takoDefiVaults[3].strategyConfig // all other contract configuration variables
    )
    const BananaEthStrategyInstance = await StrategyMasterHealer.deployed();

    console.table({
        MaticCrystalStrategy: MaticCrystalStrategyInstance.address,
        MaticTakoStrategy: MaticTakoStrategyInstance.address,
        MaticInkuStrategy: MaticInkuStrategyInstance.address,
        BananaEthStrategy: BananaEthStrategyInstance.address,
    })
};
