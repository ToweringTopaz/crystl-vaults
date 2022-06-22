task(
  "vaultWardenDeploy",
  "Deploys VaultWarden, which includes logic for both VaultHealerAuth and VaultFeeManager"
).setAction(async () => {
  const VaultWarden = await ethers.getContractFactory("VaultWarden");
  const vaultWarden = await VaultWarden.deploy();

  console.log("VaultWarden Deployed at address:", vaultWarden.address);
});

task("ascDeploy", "Deploys AmysStakingCo").setAction(async () => {
  const ASC = await ethers.getContractFactory("AmysStakingCo");
  const asc = await ASC.deploy();

  console.log("ASC Deployed at address:", asc.address);
});
task("vaultHealerAuthDeploy", "Deploys VaultHealerAuth").setAction(async () => {
  const dev = process.env.DEPLOYER_ADDRESS;

  const VaultHealerAuth = await ethers.getContractFactory("VaultHealerAuth");
  const vaultHealerAuth = await VaultHealerAuth.deploy(dev);

  console.log("VaultHealerAuth deployed at address:", vaultHealerAuth.address);
});

task("vaultFeeManagerDeploy", "Deploys VaultFeeManager")
  .addParam("vhauth", "VaultHealerAuth address to link to VaultFeeManager")
  .setAction(async ({ vhauth }) => {
    const VaultFeeManager = await ethers.getContractFactory("VaultFeeManager");
    const vaultFeeManager = await VaultFeeManager.deploy(vhauth);

    console.log(
      "VaultFeeManager deployed at address:",
      vaultFeeManager.address
    );
  });

task("ascDeploy", "Deploys AmysStakingCo").setAction(async () => {
  const ASC = await ethers.getContractFactory("AmysStakingCo");
  const asc = await ASC.deploy();

  console.log("ASC Deployed at address:", asc.address);
});
