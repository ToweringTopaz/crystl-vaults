task(
    "ascProxyDeploy",
    "Deploys Beacon Proxy with AmysStakingCo as its implementation"
  ).setAction(async () => {
    const AmysStakingCo = await ethers.getContractFactory("AmysStakingCo");
    const amysStakingCo = await AmysStakingCo.deploy();
  
    console.log("ASC Deployed at Address:", amysStakingCo.address);
  
    await amysStakingCo.deployTransaction.wait(confirms = 1)
  
    const UpgradeableBeacon = await ethers.getContractFactory(
      "UpgradeableBeacon"
    );
  
    const upgradeableBeacon = await UpgradeableBeacon.deploy(
      amysStakingCo.address
    );
    console.log(
      "Upgradable Beacon deployed at address:",
      upgradeableBeacon.address,
      " with implementation address:",
      await upgradeableBeacon.implementation()
    );
  
    await upgradeableBeacon.deployTransaction.wait(confirms = 1)
  
    const BeaconProxy = await ethers.getContractFactory("BeaconProxy");
    const beaconProxy = await BeaconProxy.deploy(
      upgradeableBeacon.address,
      "0x"
    );
  
    console.log(
      " Proxy deployed at address:",
      beaconProxy.address,
      " with beacon address:",
      upgradeableBeacon.address
    );
  });

  task("deployVaultGetter", "Deploys V3VaultGetter")
  .addParam("vh", "VaultHealer Address")
  .setAction(async ({vh}) => {
    const VaultGetterV3 = await ethers.getContractFactory("VaultGetterV3");
    const vaultGetterV3 = await VaultGetterV3.deploy(vh);

    console.log("VaultGetterV3 Deployed at address:", vaultGetterV3.address);
    await vaultGetterV3.deployTransaction.wait(1);
    await hre.run("verify:verify", {
      address: vaultGetterV3.address,
      constructorArguments: [vh]
    });
  });

  task("multiCallDeploy", "Deploys Multicall").setAction(async () => {
    const Multicall = await ethers.getContractFactory("contracts/Multicall.sol:Multicall");
    const multicall = await Multicall.deploy();
  
    console.log("Multicall deployed at address:", multicall.address);
    

    await multicall.deployTransaction.wait(confirms = 1)

    await hre.run("verify:verify", {
      address: multicall.address,
    });
  });