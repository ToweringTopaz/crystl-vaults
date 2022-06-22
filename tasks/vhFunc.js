const { task } = require("hardhat/config");

task("vhDep", "deposits the amount specified to vaulthealer")
  .addParam("vid", "vid to deposit to")
  .addParam("amt", "amount to deposit")
  .setAction(async ({ vid, amt }) => {
    const VaultHealer = new ethers.Contract(
      vaultHealerAddr,
      VaultHealerAbi,
      dev
    );
    const deposit = await VaultHealer.deposit(vid, amt, "0x", {
      gasLimit: 3000000,
    });
    console.log(deposit);
  });
