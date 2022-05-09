const MagnetiteDeploy = artifacts.require("MagnetiteDeploy");

module.exports = async function (deployer, network) {
    await deployer.deploy(MagnetiteDeploy, '0xb12ef4742163735ebc2d670039997563cf8b2a8f'); 
    const magnetiteDeploy = await MagnetiteDeploy.deployed();

    console.table({
        MagnetiteDeploy: magnetiteDeploy.address
    });
};