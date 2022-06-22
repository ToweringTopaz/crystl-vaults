const { task } = require("hardhat/config");

task("depositVH", "deposits tokens to vaulthealer")
  .addParam("vid")
  .addParam("amt")
  .addParam("vh")
  .setAction(async ({ vid, amt, vh }) => {
      const VaultHealer = await ethers.getContractAt("VaultHealer", vh);
      
      const dep = await VaultHealer.deposit(
          vid,
          amt,
          "0x"
      )
      console.log(dep)
      const hash = dep.hash
      console.log(await ethers.provider.getTransactionReceipt(hash))

  });
