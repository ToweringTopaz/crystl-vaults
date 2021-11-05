const TacticMiniApe = artifacts.require("TacticMiniApe");

module.exports = async function (deployer, network) {
    await deployer.deploy(TacticMiniApe);
    
    const TacticMiniApeInstance = await TacticMiniApe.deployed();

    console.table({
        TacticMiniApe: TacticMiniApeInstance.address,
    })
};