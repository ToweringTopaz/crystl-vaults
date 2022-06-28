task("strategyDeploy", "Deploys Strategy Implementation")
  .addParam("vh", "VaultHealer Address")
  .setAction(async ({ vh }) => {
    const Strategy = await ethers.getContractFactory("Strategy");
    const strategy = await Strategy.deploy(vh);

    console.log("Strategy deployed at address:", strategy.address);
  });

task("strategyQuickDeploy", "Deploys Strategy Contract suited for the unique DQUICK.leave method of QuickSwap")
  .addParam("vh", "VaultHealer Address")
  .setAction(async ({ vh }) => {
    const StrategyQuick = await ethers.getContractFactory("StrategyQuick");
    const strategyQuick = await StrategyQuick.deploy(vh);

    console.log("StrategyQuick deployed at address:", strategyQuick.address);
  });

task("strategyCustomRouterDeploy","Deploys a Strategy Contract suited for routers with setFee Factories")
  .addParam("vh", "VaultHealer Address")
  .setAction(async ({ vh }) => {
    const StrategyCustomRouter = await ethers.getContractFactory("StrategyCustomRouter");
    const strategyCustomRouter = await StrategyCustomRouter.deploy(vh);

    console.log("StrategyCustomRouter deployed at address:", strategyCustomRouter.address);
  })

task("strategySaharaDeploy","Deploys a Strategy suited for the unique Sahara farms, which deposit rewards to a staking pool contract")
  .addParam("vh", "VaultHealer Address")
  .setAction(async ({ vh }) => {
    const StrategySahara = await ethers.getContractFactory("StrategySahara");
    const strategyCustomRouter = await StrategyCustomRouter.deploy(vh);

    console.log("StrategySahara deployed at address:", StrategySahara.address);
  })