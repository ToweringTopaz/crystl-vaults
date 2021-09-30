const StrategyMasterHealer = artifacts.require("StrategyMasterHealerForStakingMultiRewards");
const { dokiVaults } = require('../configs/dokiVaults');

module.exports = async function (deployer, network) {
    await deployer.deploy(
        StrategyMasterHealer,
        dokiVaults[0].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...dokiVaults[0].strategyConfig // all other contract configuration variables
    )
    const AzukiMustStrategyInstance = await StrategyMasterHealer.deployed();

    await deployer.deploy(
        StrategyMasterHealer,
        dokiVaults[1].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...dokiVaults[1].strategyConfig // all other contract configuration variables
    )
    const AzukiEthStrategyInstance = await StrategyMasterHealer.deployed();

    await deployer.deploy(
        StrategyMasterHealer,
        dokiVaults[2].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...dokiVaults[2].strategyConfig // all other contract configuration variables
    )
    const DokiMustStrategyInstance = await StrategyMasterHealer.deployed();

    await deployer.deploy(
        StrategyMasterHealer,
        dokiVaults[3].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...dokiVaults[3].strategyConfig // all other contract configuration variables
    )
    const DokiEthStrategyInstance = await StrategyMasterHealer.deployed();

    console.table({
        AzukiMustStrategy: AzukiMustStrategyInstance.address,
        AzukiEthStrategy: AzukiEthStrategyInstance.address,
        DokiMustStrategy: DokiMustStrategyInstance.address,
        DokiEthStrategyInstance: DokiEthStrategyInstance.address,
    })
};
