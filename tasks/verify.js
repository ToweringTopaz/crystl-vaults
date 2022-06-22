const { task } = require("hardhat/config");

task("verifyZap", "Verifies QuartzUniV2Zap")
  .addParam("libquartz", "LibQuartz Address")
  .addParam("zap", "Zap Address")
  .addParam("vh", "VaultHealer Address")
  .setAction(async ({ libquartz, zap, vh }) => {
    await hre.run("verify:verify", {
      address: zap,
      libraries: { LibQuartz: libquartz },
      constructorArguments: [vh],
    });
  });

task("verifyVaultHealer", "Verifies VaultHealer")
  .addParam("zap", "Zap Address")
  .addParam("vh", "VaultHealer Address")
  .addParam("vhauth", "VaultHealerAuth Address")
  .addParam("feeman", "VaultFeeManager Address")
  .addParam("chonk", "VaultChonk Address")
  .setAction(async ({ zap, vh, vhauth, feeman, chonk }) => {
    await hre.run("verify:verify", {
      address: vh,
      libraries: { VaultChonk: chonk },
      constructorArguments: [vhauth, feeman, zap],
    });
  });

task(
  "verifyMagnetiteProxy",
  "Verifies Magnetite Implementation, BeaconProxy, and UpgradeableBeacon, if deployed using MagnetiteDeploy"
)
  .addParam("magdeploy", "MagnetiteDeploy Address")
  .addParam("vhauth", "VaultHealerAuth Address")
  .setAction(async ({ magdeploy, vhauth }) => {
    const MagnetiteDeploy = await ethers.getContractAt("MagnetiteDeploy", magdeploy);

    const implementation = await MagnetiteDeploy.implementation();
    const beacon = await MagnetiteDeploy.beacon();
    const proxy = await MagnetiteDeploy.proxy();
    //Verify MagnetiteDeploy
    await hre.run("verify:verify", {
      address: magdeploy,
      constructorArguments: [vhauth],
    });
    //Verify Magnetite Implementation
    await hre.run("verify:verify", {
      address: implementation,
      constructorArguments: [vhauth],
    });
    //Verify Beacon
    await hre.run("verify:verify", {
      address: beacon,
      constructorArguments: [implementation],
    });
    //Verify Proxy
    await hre.run("verify:verify", {
      address: proxy,
      constructorArguments: [beacon, "0x"],
    });
  });

task("verifyVaultWarden","VerifiesVaultWarden")
  .addParam("vaultwarden","VaultWarden Address")
  .setAction(async ({vaultwarden}) => {
    await hre.run("verify:verify", {
      address: vaultwarden,
    });
  });

task("verifyMagnetite","Verifies standalone Magnetite Implementation")
.addParam("vhauth","VaultWarden Address")
.addParam("mag","Magnetite Implementation Address")
.setAction(async ({vhauth, mag}) => {
  await hre.run("verify:verify", {
    address: mag,
    constructorArguments: [vhauth]
  });
});
