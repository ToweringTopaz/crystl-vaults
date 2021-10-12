const StrategyMiniApe = artifacts.require("StrategyMiniApe");
const { apeSwapVaults } = require('../configs/apeSwapVaults');
const { vaultSettings } = require('../configs/vaultSettings');

module.exports = async function (deployer, network) {
    await deployer.deploy(
        StrategyVHStandard,
		apeSwapVaults[0].want,
		apeSwapVaults[0].vaulthealer,
		apeSwapVaults[0].masterchef,
		apeSwapVaults[0].tactic,
		apeSwapVaults[0].PID,
		vaultSettings.standard,
		apeSwapVaults[0].earned
    )
    const MaticCrystlStrategyInstance = await StrategyMiniApe.deployed();

    await deployer.deploy(
        StrategyVHStandard,
		apeSwapVaults[1].want,
		apeSwapVaults[1].vaulthealer,
		apeSwapVaults[1].masterchef,
		apeSwapVaults[1].tactic,
		apeSwapVaults[1].PID,
		vaultSettings.standard,
		apeSwapVaults[1].earned
    )
    const MaticBananaStrategyInstance = await StrategyMiniApe.deployed();

    console.table({
        MaticCrystlStrategy: MaticCrystlStrategyInstance.address,
        MaticBananaStrategy: MaticBananaStrategyInstance.address
    })
};