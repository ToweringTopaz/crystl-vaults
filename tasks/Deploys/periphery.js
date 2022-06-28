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