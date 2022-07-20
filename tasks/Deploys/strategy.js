task("strategyDeploy", "Deploys Strategy Implementation")
  .addParam("name", "Name of the implementation contract")
  .setAction(async ({ name }) => {
    const Strategy = await ethers.getContractFactory(name);
    const strategy = await Strategy.deploy();

    console.log(name, "deployed at address:", strategy.address);
  });
  
task("getterDeploy", "Deploys VaultGetterV3")
  .addParam("vh", "VaultHealer address")
  .setAction(async ({ vh }) => {
    const Getter = await ethers.getContractFactory("VaultGetterV3");
    const getter = await Getter.deploy(vh);

    console.log("VaultGetterV3 deployed at address:", getter.address);
  });