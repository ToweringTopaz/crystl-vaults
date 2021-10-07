const StrategyMasterHealerForStakingRewards = artifacts.require("StrategyMasterHealerForStakingRewards");
const { dfynVaults } = require('../configs/dfynVaults');

module.exports = async function (deployer, network) {
    await deployer.deploy(
        StrategyMasterHealerForStakingRewards,
        dfynVaults[0].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...dfynVaults[0].strategyConfig // all other contract configuration variables
    )
    const StrategyMasterHealerForStakingRewardsInstance = await StrategyMasterHealerForStakingRewards.deployed();

    console.table({
        DfynStrategy: StrategyMasterHealerForStakingRewardsInstance.address,
    })
};