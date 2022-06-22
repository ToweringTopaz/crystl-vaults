const { task } = require("hardhat/config");

task("prepareDeploy", "Deploys VaultDeploy contract for Advanced, quick deployment. Uses computed VaultHealer address")
    .setAction(async (taskArgs) => {
	
	vaultDeploy = await ethers.getContractFactory("VaultDeploy");
	
	[user0, _] = await ethers.getSigners();
	console.log("User account is ", user0.address);
	
	nonce = await user0.getTransactionCount()
	vaultDeploy = await vaultDeploy.deploy(nonce);
	
	console.log("VaultDeploy deployed at :", vaultDeploy.address);
	console.log("Constructor parameter was a nonce of", nonce);
});

task("vaultHealer", "Advanced deployment of VaultHealer using VaultDeploy flow")
  .addParam("chonk", "The VaultChonk library address")
  .addParam("depl", "VaultDeploy address")
  .setAction(async ({ chonk, depl }) => {

	vaultDeploy = await ethers.getContractAt("VaultDeploy", depl);
    vaultHealer = await ethers.getContractFactory("VaultHealer", {libraries: { VaultChonk: chonk }});
    vaultHealer = await vaultHealer.deploy(await vaultDeploy.vhAuth(), await vaultDeploy.vaultFeeManager(), await vaultDeploy.zap());
    
    console.log("New VaultHealer address: ", vaultHealer.address);
	
  });