import hre from "hardhat";
import { Artifact } from "hardhat/types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { StrategyMasterHealer } from "../../typechain/StrategyMasterHealer";
import { TestVaultHealer } from "../../typechain/TestVaultHealer";
import { LiquidityPool, Signers } from "../types";
import { shouldBehaveLikeStrategyMasterHealer } from "./StrategyMasterHealer.behaviour";
import { shouldStakeLikeStrategyMasterHealer } from "./StrategyMasterHealer.behaviour";
import { default as BeefyStakingPools } from "../beefy.staking-pools.json";
import { IUniswapV2Router02 } from "../../typechain";
import { getOverrideOptions } from "../utils";
import { getAddress } from "ethers/lib/utils";


const { deployContract } = hre.waffle;

describe("Unit tests", function () {
  before(async function () {
    this.signers = {} as Signers;

    const signers: SignerWithAddress[] = await hre.ethers.getSigners();

    this.signers.admin = signers[0];
    this.signers.owner = signers[1];
    this.signers.deployer = signers[2];
    this.signers.alice = signers[3];

    // get the UniswapV2Router contract instance
    this.uniswapV2Router02 = <IUniswapV2Router02>(
      await hre.ethers.getContractAt("IUniswapV2Router02", "0xC0788A3aD43d79aa53B09c2EaCc313A787d1d607") //changed this to polygon apeswap router
    );

    // deploy Strategy Master Healer
    const strategyMasterHealerArtifact: Artifact = await hre.artifacts.readArtifact("StrategyMasterHealer");
    this.strategyMasterHealer = <StrategyMasterHealer>(
      await deployContract(this.signers.deployer, strategyMasterHealerArtifact, [], getOverrideOptions())
    );

    // deploy TestVaultHealer Contract
    const testVaultHealerArtifact: Artifact = await hre.artifacts.readArtifact("TestVaultHealer");
    this.testVaultHealer = <TestVaultHealer>(
      await deployContract(this.signers.deployer, testVaultHealerArtifact, [], getOverrideOptions())
    );

    for (const pool of Object.values(BeefyFinancePools)) {
      if (!pool.whale) {
        throw new Error(`Whale is missing for ${pool.pool}`);
      }

      const WHALE: string = getAddress(String(pool.whale));

      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [WHALE],
      });

      const WHALE_SIGNER = await hre.ethers.getSigner(WHALE);
      const POOL_TOKEN_CONTRACT = await hre.ethers.getContractAt("IERC20", pool.tokens[0], WHALE_SIGNER);
      const underlyingTokenInstance2 = await hre.ethers.getContractAt("ERC20", pool.tokens[0]);
      const TOKEN_DECIMALS = await underlyingTokenInstance2.decimals();
      console.log(await underlyingTokenInstance2.balanceOf(WHALE));

      // fund the whale's wallet with gas
      await this.signers.admin.sendTransaction({
        to: WHALE,
        value: hre.ethers.utils.parseEther("1000"),
        ...getOverrideOptions(),
      });

      // fund TestVaultHealer with 5 tokens each
      await POOL_TOKEN_CONTRACT.transfer(
        this.testVaultHealer.address,
        hre.ethers.utils.parseUnits("1", TOKEN_DECIMALS),
        getOverrideOptions(),
      );
    }
  });

  describe("StrategyMasterHealer", function () {
    Object.keys(BeefyFinancePools).map(async (token: string) => {
      shouldBehaveLikeStrategyMasterHealer(token, (BeefyFinancePools as LiquidityPool)[token]);
    });
  });

  describe("StrategyMasterHealer", function () {
    Object.keys(BeefyStakingPools).map(async (token: string) => {
      shouldStakeLikeStrategyMasterHealer(token, (BeefyStakingPools as LiquidityPool)[token]);
    });
  });
});
