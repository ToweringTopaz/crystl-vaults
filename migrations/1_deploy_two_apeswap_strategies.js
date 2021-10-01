const StrategyMiniApe = artifacts.require("StrategyMiniApe");
const { apeSwapVaults } = require('../configs/apeSwapVaults');
const { vaultSettings } = require('../configs/vaultSettings');

module.exports = async function (deployer, network) {
    await deployer.deploy(
        StrategyUnified,
		apeSwapVaults[0].masterchef,
		apeSwapVaults[0].tactic,
		apeSwapVaults[0].PID,
		apeSwapVaults[0].vaulthealer,
		apeSwapVaults[0].want,
		vaultSettings.standard,
		apeSwapVaults[0].earned,
        apeSwapVaults[0].paths
    )
    const MaticCrystlStrategyInstance = await StrategyMiniApe.deployed();

    await deployer.deploy(
        StrategyUnified,
		apeSwapVaults[1].masterchef,
		apeSwapVaults[1].tactic,
		apeSwapVaults[1].PID,
		apeSwapVaults[1].vaulthealer,
		apeSwapVaults[1].want,
		vaultSettings.standard,
		apeSwapVaults[1].earned,
        apeSwapVaults[1].paths
    )
    const MaticBananaStrategyInstance = await StrategyMiniApe.deployed();

    console.table({
        MaticCrystlStrategy: MaticCrystlStrategyInstance.address,
        MaticBananaStrategy: MaticBananaStrategyInstance.address
    })
};