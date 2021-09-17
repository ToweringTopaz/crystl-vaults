const StrategyMasterHealerWithReferral = artifacts.require("StrategyMasterHealerWithReferral");
const { polyrollVaults } = require('../configs/polyrollVaults');

module.exports = async function (deployer, network) {
    await deployer.deploy(
        StrategyMasterHealerWithReferral,
        polyrollVaults[0].addresses, // configuration addresses: vaulthealer, masterchef, unirouter, want, earned
        ...polyrollVaults[0].strategyConfig // all other contract configuration variables
    )
    const StrategyMasterHealerWithReferralInstance = await StrategyMasterHealerWithReferral.deployed();

    console.table({
        PolyRollStrategy: StrategyMasterHealerWithReferralInstance.address,
    })
};