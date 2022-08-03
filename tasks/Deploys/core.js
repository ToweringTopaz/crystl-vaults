const { tokens } = require("../../configs/addresses");

task(
  "spawnV3",
  "An aggregate task that combines all deployments and verifications of core V3 Contracts"
)
  .addParam(
    "verify",
    "boolean to represent whether to attempt automatic verifications"
  )
  .setAction(async ({ verify }) => {
    /*could probably make this faster by awaiting for all getContractFactory promises to resolve
    into an object and then deploying and stuff but hi ho, sometimes slow is fine.

    Some chains have slower txn inclusion, so we wait for the deployments to be confirmed before we continue on,
    also prevents conditions in which there is no bytecode at a contract address upon auto-verification :) */

    console.log("DEPLOYING VAULTCHONK");
    const VaultChonk = await ethers.getContractFactory("VaultChonk");
    const vaultChonk = await VaultChonk.deploy();
    console.log(
      `VAULTCHONK DEPLOYED @ ADDRESS:" ${vaultChonk.address}...WAITING FOR CONFIRMATION`
    );
    await vaultChonk.deployTransaction.wait(1);

    console.log("DEPLOYING LIBQUARTZ");
    const LibQuartz = await ethers.getContractFactory("LibQuartz");
    const libQuartz = await LibQuartz.deploy();
    console.log(
      `LIBQUARTZ DEPLOYED @ ADDRESS: ${libQuartz.address}... WAITING FOR CONFIRMATION`
    );
    await vaultChonk.deployTransaction.wait(1);

    console.log("DEPLOYING VAULTWARDEN");
    const VaultWarden = await ethers.getContractFactory("VaultWarden");
    const vaultWarden = await VaultWarden.deploy();
    console.log(
      `VAULTWARDEN DEPLOYED @ ADDRESS ${vaultWarden.address}... WAITING FOR CONFIRMATION`
    );
    await vaultWarden.deployTransaction.wait(1);

    console.log("DEPLOYING ZAP AND DETERMINING VAULTHEALERADDRESS");
    const dev = process.env.DEPLOYER_ADDRESS;
    const Zap = await ethers.getContractFactory("QuartzUniV2Zap", {
      libraries: { LibQuartz: libQuartz.address },
    });
    const nonce = await ethers.provider.getTransactionCount(dev);
    const derivedVaultHealerAddress = ethers.utils.getContractAddress({
      from: dev,
      nonce: nonce + 1,
    });
    const zap = await Zap.deploy(derivedVaultHealerAddress);
    console.log(
      `ZAP DEPLOYED @ ADDRESS: ${zap.address}... WAITING FOR CONFIRMATION`
    );
    await zap.deployTransaction.wait(1);

    console.log("DEPLOYING VAULTHEALER");
    const VaultHealer = await ethers.getContractFactory("VaultHealer", {
      libraries: { VaultChonk: vaultChonk.address },
    });
    const vaultHealer = await VaultHealer.deploy(
      vaultWarden.address,
      vaultWarden.address,
      zap.address
    );
    console.log(
      `VAULTHEALER DEPLOYED @ ADDRESS: ${vaultHealer.address}... WAITING FOR CONFIRMATION`
    );
    await vaultHealer.deployTransaction.wait(1);

    console.log("DEPLOYING BOILERPLATE STRATEGY IMPLEMENTATION CONTRACT");
    const Strategy = await ethers.getContractFactory("Strategy");
    const strategy = await Strategy.deploy();
    console.log(
      `BOILERPLATE STRATEGY IMPLEMENTATION DEPLOYED @ ADDRESS ${strategy.address}...WAITING FOR CONFIRMATION`
    );
    await strategy.deployTransaction.wait(1);

    console.log("DEPLOYING BOOST POOL IMPLEMENTATION");
    const BoostPool = await ethers.getContractFactory("BoostPool");
    const boostPool = await BoostPool.deploy(vaultHealer.address);
    console.log(
      `BOOSTPOOL IMPLEMENTATION DEPLOYED @ ADDRESS ${boostPool.address}...WAITING FOR CONFIRMATION`
    );
    await boostPool.deployTransaction.wait(1);

    /* 
    Okay this is where things get a bit funky,  we'll use a try catch here. 
    If Magnetite is not correctly configured for the given blockchain, it should throw an error
    so we need to handle that accordingly.
    */

    console.log("DEPLOYING MAGNETITE PROXY...");
    const Addresses = {
      VaultChonk: vaultChonk.address,
      LibQuartz: libQuartz.address,
      VaultWarden: vaultWarden.address,
      Zap: zap.address,
      VaultHealer: vaultHealer.address,
      Strategy: strategy.address,
      BoostPool: boostPool.address,
      MagnetiteImplementation: undefined,
      MagnetiteBeacon: undefined,
      MagnetiteProxy: undefined,
    };
    try {
      const MagnetiteDeploy = await ethers.getContractFactory(
        "MagnetiteDeploy"
      );
      const magnetiteDeploy = await MagnetiteDeploy.deploy(vaultWarden.address);
      console.log(
        `MAGNETITEDEPLOY DEPLOYED @ ADDRESS: ${magnetiteDeploy.address}...WAITING FOR CONFIRMATION`
      );
      await magnetiteDeploy.deployTransaction.wait(1);
      const magImpl = await magnetiteDeploy.implementation();
      const magBeacon = await magnetiteDeploy.beacon();
      const magProxy = await magnetiteDeploy.proxy();
      console.log(`MAGNETITE IMPLEMENTATION DEPLOYED @ ADDRESS: ${magImpl}`);
      console.log(`BEACON ADDRESS: ${magBeacon}`);
      console.log(`PROXY ADDRESS: ${magProxy}`);

       Addresses.MagnetiteImplementation = magImpl;
       Addresses.MagnetiteBeacon = magBeacon;
       Addresses.MagnetiteProxy = magProxy
      }catch {
      throw new Error(
        "MAGNETITE DEPLOY FAILED. PLEASE MAKE SURE YOU SET UP THE CONTRACT WITH THE CORRECT ADDRESSES "
      );
    }
    if (verify) {
      /* now we'll try programatic verification */
      await Promise.all([
        hre.run("verify:verify", {
          address: Addresses.VaultChonk,
        }),
        hre.run("verify:verify", {
          address: Addresses.LibQuartz,
        }),
        hre.run("verify:verify", {
          address: Addresses.VaultWarden,
        }),
        hre.run("verify:verify", {
          address: Addresses.Zap,
          libraries: { LibQuartz: Addresses.LibQuartz },
          constructorArguments: [Addresses.VaultHealer],
        }),
        hre.run("verify:verify", {
          address: Addresses.VaultHealer,
          libraries: { VaultChonk: Addresses.VaultChonk },
          constructorArguments: [
            Addresses.VaultWarden,
            Addresses.VaultWarden,
            Addresses.Zap,
          ],
        }),
        hre.run("verify:verify", {
          address: Addresses.Strategy,
        }),
        hre.run("verify:verify", {
          address: Addresses.BoostPool,
          constructorArguments: [Addresses.VaultHealer],
        }),
      ]);
      //now that the core contracts are verified, we'll try to verify magnetite. This can be error prone so to handle those we'll try-catch
      try {
        await Promise.all([
          await hre.run("verify:verify", {
            address: magdeploy,
            constructorArguments: [vhauth],
          }),
          //Verify Magnetite Implementation
          await hre.run("verify:verify", {
            address: implementation,
            constructorArguments: [vhauth],
          }),
          //Verify Beacon
          await hre.run("verify:verify", {
            address: beacon,
            constructorArguments: [implementation],
          }),
          //Verify Proxy
          await hre.run("verify:verify", {
            address: proxy,
            constructorArguments: [beacon, "0x"],
          }),
        ]);
      } catch {
        throw new Error ("MAGNETITE VERIFICATION FAILED.")
      }
    }
  });

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

  await amysStakingCo.deployTransaction.wait((confirms = 1));

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

  await upgradeableBeacon.deployTransaction.wait((confirms = 1));

  const BeaconProxy = await ethers.getContractFactory("BeaconProxy");
  const beaconProxy = await BeaconProxy.deploy(upgradeableBeacon.address, "0x");

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
      [t.WCRO, t.VVS, t.FER],
    ];
    for (let i = 0; i < PATHS.length; i++) {
      var update = await MagnetiteProxy.overridePath(router, PATHS[i]);
      console.log("Path", i, "updated to:", PATHS[i], update.hash);
    }
  });
