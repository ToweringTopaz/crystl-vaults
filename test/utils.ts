import hre, { network } from "hardhat";
const { ethers } = require("hardhat");
import { ERC20 } from "../typechain";


const setStorageAt = (address: string, slot: string, val: string) =>
  hre.network.provider.send("hardhat_setStorageAt", [address, slot, val]);

const tokenBalancesSlot = async (token: ERC20) => {
  const val: string = "0x" + "12345".padStart(64, "0");
  const account: string = ethers.constants.AddressZero;

  for (let i = 0; i < 100; i++) {
    let slot = ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [account, i]));
    while (slot.startsWith("0x0")) slot = "0x" + slot.slice(3);

    const prev = await hre.network.provider.send("eth_getStorageAt", [account, slot, "latest"]);
    await setStorageAt(token.address, slot, val);
    const balance = await token.balanceOf(account);
    await setStorageAt(token.address, slot, prev);
    if (balance.eq(ethers.BigNumber.from(val))) {
      return { index: i, isVyper: false };
    }
  }

  for (let i = 0; i < 100; i++) {
    let slot = ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(["uint256", "address"], [i, account]));
    while (slot.startsWith("0x0")) slot = "0x" + slot.slice(3);

    const prev = await hre.network.provider.send("eth_getStorageAt", [account, slot, "latest"]);
    await setStorageAt(token.address, slot, val);
    const balance = await token.balanceOf(account);
    await setStorageAt(token.address, slot, prev);
    if (balance.eq(ethers.BigNumber.from(val))) {
      return { index: i, isVyper: true };
    }
  }
  throw "balances slot not found!";
};

// Source : https://blog.euler.finance/brute-force-storage-layout-discovery-in-erc20-contracts-with-hardhat-7ff9342143ed
export async function setTokenBalanceInStorage(token: ERC20, account: string, amount: string) {
  const balancesSlot = await tokenBalancesSlot(token);
  if (balancesSlot.isVyper) {
    return setStorageAt(
      token.address,
      ethers.utils.keccak256(
        ethers.utils.defaultAbiCoder.encode(["uint256", "address"], [balancesSlot.index, account]),
      ),
      "0x" +
        ethers.utils
          .parseUnits(amount, await token.decimals())
          .toHexString()
          .slice(2)
          .padStart(64, "0"),
    );
  } else {
    return setStorageAt(
      token.address,
      ethers.utils.hexStripZeros(
        ethers.utils.keccak256(
          ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [account, balancesSlot.index]),
        ),
      ),
      "0x" +
        ethers.utils
          .parseUnits(amount, await token.decimals())
          .toHexString()
          .slice(2)
          .padStart(64, "0"),
    );
  }
}

export const advanceBlock = async () => {
  return await ethers.provider.send("evm_mine", [])
}

export const advanceBlockTo = async (blockNumber: number) => {
  for (let i = await ethers.provider.getBlockNumber(); i < blockNumber; i++) {
    await advanceBlock()
  }
}

export const advanceBlockWithNumber = async (blockNumber: number) => {
  for (let i = 0; i < blockNumber; i++) 
    await advanceBlock()
}

export const setBalance = async (addr: string, balance: string) => {
  await network.provider.send("hardhat_setBalance", [
    addr,
    balance,
  ]);
}

export const increaseTime = async (time: number) => {
  await network.provider.send("evm_increaseTime", [time]);
}

