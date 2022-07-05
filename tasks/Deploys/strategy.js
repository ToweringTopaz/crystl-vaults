task("strategyDeploy", "Deploys Strategy Implementation")
  .addParam("name", "Name of the implementation contract")
  .setAction(async ({ name }) => {
    const Strategy = await ethers.getContractFactory(name);
    const strategy = await Strategy.deploy();

    console.log(name, "deployed at address:", strategy.address);
  });