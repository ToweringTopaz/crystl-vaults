const { tokens } = require("../../configs/addresses");

task("chonkDeploy", "Deploys VaultChonk Library").setAction(async () => {
  const VaultChonk = await ethers.getContractFactory("VaultChonk");
  const vaultChonk = await VaultChonk.deploy();

  console.log("VaultChonk deployed at address:", vaultChonk.address);
});

task("libQuartzDeploy", "Deploys LibQuartz").setAction(async () => {
  const LibQuartz = await ethers.getContractFactory("LibQuartz");
  const libQuartz = await LibQuartz.deploy();

  console.log("LibQuartz Deployed at address:", libQuartz.address);
});

task(
  "vaultWardenDeploy",
  "Deploys VaultWarden, which includes logic for both VaultHealerAuth and VaultFeeManager"
).setAction(async () => {
  const VaultWarden = await ethers.getContractFactory("VaultWarden");
  const vaultWarden = await VaultWarden.deploy();

  console.log("VaultWarden Deployed at address:", vaultWarden.address);
});

task("zapDeploy", "Deploys Zap Contract, linking to the LibQuartz Library")
  .addParam("libquartz", "LibQuartz Address")
  .setAction(async ({ libquartz }) => {
    const dev = process.env.DEPLOYER_ADDRESS;
    const Zap = await ethers.getContractFactory("QuartzUniV2Zap", {
      libraries: { LibQuartz: libquartz },
    });

    const nonce = await ethers.provider.getTransactionCount(dev);
    console.log("Nonce is:", nonce);

    const derivedVaultHealerAddress = ethers.utils.getContractAddress({
      from: dev,
      nonce: nonce + 1,
    });

    const zap = await Zap.deploy(derivedVaultHealerAddress);
    console.log("Future VH Address:", derivedVaultHealerAddress);
    console.warn(
      "YOU ABSOLUTELY MUST DEPLOY VAULTHEALER FOLLOWING COMPLETION OF THIS DEPLOYMENT"
    );
    console.log("Zap deployed at address:", zap.address);
  });

task("vaultHealerDeploy", "deploys VaultHealer, linking to VaultChonk library")
  .addParam("chonk", "VaultChonk Address")
  .addParam("vhauth", "VaultHealerAuth Address")
  .addParam("feeman", "VaultFeeManager Address")
  .addParam("zap", "QuartzUniV2ZapAddress")
  .setAction(async ({ chonk, vhauth, feeman, zap }) => {
    const VaultHealer = await ethers.getContractFactory("VaultHealer", {
      libraries: { VaultChonk: chonk },
    });
    const vaultHealer = await VaultHealer.deploy(vhauth, feeman, zap);

    console.log("VaultHealer deployed at address:", vaultHealer.address);
  });

task("boostPoolDeploy", "Deploys BoostPool Implementation")
  .addParam("vh", "VaultHealer Address")
  .setAction(async ({ vh }) => {
    const BoostPool = await ethers.getContractFactory("BoostPool");
    const boostPool = await BoostPool.deploy(vh);

    console.log("BoostPool deployed at address:", boostPool.address);
  });

task(
  "magnetiteProxyDeploy",
  "Deploys Beacon Proxy with Magnetite as its implementation"
)
  .addParam("vhauth", "VaultHealerAuth Address")
  .setAction(async ({ vhauth }) => {
    const MagnetiteDeploy = await ethers.getContractFactory("MagnetiteDeploy");
    const magnetiteDeploy = await MagnetiteDeploy.deploy(vhauth);

    console.log(
      "MagnetiteDeploy Deployed at address:",
      magnetiteDeploy.address
    );

    console.log(
      "Magnetite Implementation deployed at address:",
      await magnetiteDeploy.implementation()
    );
    console.log("Beacon Address:", await magnetiteDeploy.beacon());
    console.log("Proxy Address:", await magnetiteDeploy.proxy());
  });

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

task(
  "upgradeMagnetite",
  "Deploys a fresh instance of Magnetite, and upgrades the beacon address provided"
)
  .addParam("beacon", "Beacon Address")
  .addParam("vhauth", "VaultHealerAuthAddress")
  .setAction(async ({ beacon, vhauth }) => {
    const Magnetite = await ethers.getContractFactory("Magnetite");
    const magnetite = await Magnetite.deploy(vhauth);

    console.log(
      "Magnetite Implementation deployed at addrress:",
      magnetite.address
    );

    const Beacon = await ethers.getContractAt("UpgradeableBeacon", beacon);
    await provider.waitForTransaction(magnetite.hash);
    const Upgrade = await Beacon.upgradeTo(magnetite.address);

    console.log(
      "Beacon at address:",
      Beacon.address,
      " upgraded to implementation:",
      magnetite.address,
      "TxnHash:",
      Upgrade.hash
    );
  });

task("overridePath", "Quick way to update Pathing")
  .addParam("magproxy", "address of the magnetite Proxy")
  .addParam("router", "address of the router to change pathing for")
  .setAction(async ({ magproxy, router }) => {
    const MagnetiteProxy = await ethers.getContractAt("Magnetite", magproxy);
    let t = tokens.cronos; //make sure to change this to resepctive network
    let PATHS = [
      [t.FER, t.VVS],
      [t.VVS, t.FER],
      [t.FER, t.VVS, t.WCRO],
      [t.WCRO, t.VVS, t.FER]

    ];
    for (let i = 0; i < PATHS.length; i++) {
      var update = await MagnetiteProxy.overridePath(router, PATHS[i]);
      console.log("Path", i, "updated to:", PATHS[i], update.hash);
    }
  });

task("deployVaultGetterV3", "Deploys V3VaultGetter")
  .addParam("vh", "VaultHealer Address")
  .setAction(async () => {
    const VaultGetterV3 = await ethers.getContractFactory("VaultGetterV3");
    const vaultGetterV3 = await VaultGetterV3.deploy(vh);

    console.log("VaultGetterV3 Deployed at address:", vaultGetterV3.address);
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