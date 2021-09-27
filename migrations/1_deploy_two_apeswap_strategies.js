const StrategyMiniApe = artifacts.require("StrategyMiniApe");
const { apeSwapVaults } = require('../configs/apeSwapVaults');
const { vaultSettings } = require('../configs/vaultSettings');

module.exports = async function (deployer, network) {
    await deployer.deploy(
        StrategyMiniApe,
        apeSwapVaults[0].addresses,
		vaultSettings.standard,
        apeSwapVaults[0].paths
    )
    const MaticCrystlStrategyInstance = await StrategyMiniApe.deployed();

    await deployer.deploy(
        StrategyMiniApe,
        apeSwapVaults[1].addresses,
		vaultSettings.standard,
        ...apeSwapVaults[1].paths
    )
    const MaticBananaStrategyInstance = await StrategyMiniApe.deployed();

    console.table({
        MaticCrystlStrategy: MaticCrystlStrategyInstance.address,
        MaticBananaStrategy: MaticBananaStrategyInstance.address
    })
};