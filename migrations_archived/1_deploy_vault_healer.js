const VaultHealer = artifacts.require("VaultHealer");

module.exports = async function (deployer, network) {
    await deployer.deploy(VaultHealer); 
    const vaultHealer = await VaultHealer.deployed();

    console.table({
        VaultHealer: vaultHealer.address
    });
};