import hre from "hardhat";
import chai, { expect } from "chai";
import { solidity } from "ethereum-waffle";
import { getAddress } from "ethers/lib/utils";
import { BigNumber, utils } from "ethers";
import { PoolItem } from "../types";
import { getOverrideOptions } from "../utils";

chai.use(solidity);

export function shouldBehaveLikeStrategyMasterHealer(token: string, pool: PoolItem): void {
  it(`should deposit ${token} to and withdraw ${token} from ${token} pool of Beefy Finance`, async function () {
    // beefy finance's deposit vault instance
    const beefyDepositInstance = await hre.ethers.getContractAt("IBeefyDeposit", pool.pool);
    // beefy lpToken decimals
    const decimals = await beefyDepositInstance.decimals();
    // underlying token instance
    const underlyingTokenInstance = await hre.ethers.getContractAt("IERC20", pool.tokens[0]);
    // 1. deposit all underlying tokens
    await this.testVaultHealer.testGetDepositAllCodes(
      pool.tokens[0], //e.g. USDC, DAI, WETH, WBTC
      pool.pool, //the address of the vault we're paying into
      this.strategyMasterHealer.address, //what is this?
      getOverrideOptions(),
    );
    // 1.1 assert whether lptoken balance is as expected or not after deposit
    const actualLPTokenBalanceAfterDeposit = await this.strategyMasterHealer.getLiquidityPoolTokenBalance(
      this.testVaultHealer.address,
      this.testVaultHealer.address, // placeholder of type address
      pool.pool,
    );
    const expectedLPTokenBalanceAfterDeposit = await beefyDepositInstance.balanceOf(this.testVaultHealer.address);
    expect(actualLPTokenBalanceAfterDeposit).to.be.eq(expectedLPTokenBalanceAfterDeposit);

    // 1.2 assert whether underlying token balance is as expected or not after deposit
    const actualUnderlyingTokenBalanceAfterDeposit = await this.testVaultHealer.getERC20TokenBalance(
      (
        await this.strategyMasterHealer.getUnderlyingTokens(pool.pool, pool.pool)
      )[0],
      this.testVaultHealer.address,
    );
    const expectedUnderlyingTokenBalanceAfterDeposit = await underlyingTokenInstance.balanceOf(
      this.testVaultHealer.address,
    );
    expect(actualUnderlyingTokenBalanceAfterDeposit).to.be.eq(expectedUnderlyingTokenBalanceAfterDeposit);
    // 1.3 assert whether the amount in token is as expected or not after depositing
    const actualAmountInTokenAfterDeposit = await this.strategyMasterHealer.getAllAmountInToken(
      this.testVaultHealer.address,
      pool.tokens[0],
      pool.pool,
    );
    const pricePerFullShareAfterDeposit = await beefyDepositInstance.getPricePerFullShare();
    const expectedAmountInTokenAfterDeposit = BigNumber.from(expectedLPTokenBalanceAfterDeposit)
      .mul(BigNumber.from(pricePerFullShareAfterDeposit))
      .div(BigNumber.from("10").pow(BigNumber.from(decimals)));
    expect(actualAmountInTokenAfterDeposit).to.be.eq(expectedAmountInTokenAfterDeposit);

    // 6. Withdraw all lpToken balance
    await this.testVaultHealer.testGetWithdrawAllCodes(
      pool.tokens[0],
      pool.pool,
      this.strategyMasterHealer.address,
      getOverrideOptions(),
    );
    // 6.1 assert whether lpToken balance is as expected or not
    const actualLPTokenBalanceAfterWithdraw = await this.strategyMasterHealer.getLiquidityPoolTokenBalance(
      this.testVaultHealer.address,
      this.testVaultHealer.address, // placeholder of type address
      pool.pool,
    );
    const expectedLPTokenBalanceAfterWithdraw = await beefyDepositInstance.balanceOf(this.testVaultHealer.address);
    expect(actualLPTokenBalanceAfterWithdraw).to.be.eq(expectedLPTokenBalanceAfterWithdraw);
    // 6.2 assert whether underlying token balance is as expected or not after withdraw
    const actualUnderlyingTokenBalanceAfterWithdraw = await this.testVaultHealer.getERC20TokenBalance(
      (
        await this.strategyMasterHealer.getUnderlyingTokens(pool.pool, pool.pool)
      )[0],
      this.testVaultHealer.address,
    );
    const expectedUnderlyingTokenBalanceAfterWithdraw = await underlyingTokenInstance.balanceOf(
      this.testVaultHealer.address,
    );
    expect(actualUnderlyingTokenBalanceAfterWithdraw).to.be.eq(expectedUnderlyingTokenBalanceAfterWithdraw);
  });
}

export function shouldStakeLikeStrategyMasterHealer(token: string, pool: PoolItem): void {
  it(`should stake mooPolygon${token} ,claim rewards, and then unstake and withdraw mooPolygon${token} from mooPolygon${token} staking pool of Beefy Finance`, async function () {
    // beefy finance's deposit vault instance
    const beefyDepositInstance = await hre.ethers.getContractAt("IBeefyDeposit", pool.pool);
    // beefy lpToken decimals
    const decimals = await beefyDepositInstance.decimals();
    // beefy finance's staking vault instance
    const beefyStakingInstance = await hre.ethers.getContractAt("IBeefyFarm", pool.stakingPool as string);
    // beefy finance reward token's instance
    const farmRewardInstance = await hre.ethers.getContractAt("IERC20", (pool.rewardTokens as string[])[0]);
    // underlying token instance
    const underlyingTokenInstance = await hre.ethers.getContractAt("IERC20", pool.tokens[0]);
    // 1. deposit all underlying tokens
    await this.testVaultHealer.testGetDepositAllCodes(
      pool.tokens[0],
      pool.pool,
      this.strategyMasterHealer.address,
      getOverrideOptions(),
    );
    // 1.1 assert whether lptoken balance is as expected or not after deposit
    const actualLPTokenBalanceAfterDeposit = await this.strategyMasterHealer.getLiquidityPoolTokenBalance(
      this.testVaultHealer.address,
      this.testVaultHealer.address, // placeholder of type address
      pool.pool,
    );
    const expectedLPTokenBalanceAfterDeposit = await beefyDepositInstance.balanceOf(this.testVaultHealer.address);
    expect(actualLPTokenBalanceAfterDeposit).to.be.eq(expectedLPTokenBalanceAfterDeposit);

    // 1.2 assert whether underlying token balance is as expected or not after deposit
    const actualUnderlyingTokenBalanceAfterDeposit = await this.testVaultHealer.getERC20TokenBalance(
      (
        await this.strategyMasterHealer.getUnderlyingTokens(pool.pool, pool.pool)
      )[0],
      this.testVaultHealer.address,
    );
    const expectedUnderlyingTokenBalanceAfterDeposit = await underlyingTokenInstance.balanceOf(
      this.testVaultHealer.address,
    );
    expect(actualUnderlyingTokenBalanceAfterDeposit).to.be.eq(expectedUnderlyingTokenBalanceAfterDeposit);
    // 1.3 assert whether the amount in token is as expected or not after depositing
    const actualAmountInTokenAfterDeposit = await this.strategyMasterHealer.getAllAmountInToken(
      this.testVaultHealer.address,
      pool.tokens[0],
      pool.pool,
    );
    const pricePerFullShareAfterDeposit = await beefyDepositInstance.getPricePerFullShare();
    const expectedAmountInTokenAfterDeposit = BigNumber.from(expectedLPTokenBalanceAfterDeposit)
      .mul(BigNumber.from(pricePerFullShareAfterDeposit))
      .div(BigNumber.from("10").pow(BigNumber.from(decimals)));
    expect(actualAmountInTokenAfterDeposit).to.be.eq(expectedAmountInTokenAfterDeposit);
    // 2. stake all lpTokens
    await this.testVaultHealer.testGetStakeAllCodes(
      pool.pool,
      pool.tokens[0],
      this.strategyMasterHealer.address,
      getOverrideOptions(),
    );
    // 2.1 assert whether the staked lpToken balance is as expected or not after staking lpToken
    const actualStakedLPTokenBalanceAfterStake = await this.strategyMasterHealer.getLiquidityPoolTokenBalanceStake(
      this.testVaultHealer.address,
      pool.pool,
    );
    const expectedStakedLPTokenBalanceAfterStake = await beefyStakingInstance.balanceOf(this.testVaultHealer.address);
    expect(actualStakedLPTokenBalanceAfterStake).to.be.eq(expectedStakedLPTokenBalanceAfterStake);

    // 2.2 assert whether the reward token is as expected or not
    const actualRewardToken = await this.strategyMasterHealer.getRewardToken(pool.pool);
    const expectedRewardToken = (pool.rewardTokens as string[])[0];
    expect(getAddress(actualRewardToken)).to.be.eq(getAddress(expectedRewardToken));
    // 2.3 make a transaction for mining a block to get finite unclaimed reward amount
    await this.signers.admin.sendTransaction({
      value: utils.parseEther("0"),
      to: await this.signers.admin.getAddress(),
      ...getOverrideOptions(),
    });
    // 2.4 assert whether the unclaimed reward amount is as expected or not after staking
    const actualUnclaimedRewardAfterStake = await this.strategyMasterHealer.getUnclaimedRewardTokenAmount(
      this.testVaultHealer.address,
      pool.pool,
      pool.tokens[0],
    );
    const expectedUnclaimedRewardAfterStake = await beefyStakingInstance.earned(this.testVaultHealer.address);
    expect(actualUnclaimedRewardAfterStake).to.be.eq(expectedUnclaimedRewardAfterStake);
    // 2.5 assert whether the amount in token is as expected or not after staking
    const actualAmountInTokenAfterStake = await this.strategyMasterHealer.getAllAmountInTokenStake(
      this.testVaultHealer.address,
      pool.tokens[0],
      pool.pool,
    );
    // get price per full share of the beefy lpToken
    const pricePerFullShareAfterStake = await beefyDepositInstance.getPricePerFullShare();
    // get amount in underlying token if reward token is swapped
    //COMMENTED OUT UNTIL SUFFICIENT LIQUIDITY IN WATCH FOR APESWAP/QUICKSWAP CALLS NOT TO REVERT
    // const rewardInTokenAfterStake = (
    //   await this.uniswapV2Router02.getAmountsOut(expectedUnclaimedRewardAfterStake, [
    //     expectedRewardToken,
    //     await this.uniswapV2Router02.WETH(),
    //     pool.tokens[0],
    //   ])
    // )[2];

    // // calculate amount in token for staked lpToken
    //COMMENTED OUT UNTIL SUFFICIENT LIQUIDITY IN WATCH FOR QUICKSWAP CALLS NOT TO REVERT
    // const expectedAmountInTokenFromStakedLPTokenAfterStake = BigNumber.from(expectedStakedLPTokenBalanceAfterStake)
    //   .mul(BigNumber.from(pricePerFullShareAfterStake))
    //   .div(BigNumber.from("10").pow(BigNumber.from(decimals)));
    // // calculate total amount token when lpToken is redeemed plus reward token is harvested
    // const expectedAmountInTokenAfterStake = BigNumber.from(rewardInTokenAfterStake).add(
    //   expectedAmountInTokenFromStakedLPTokenAfterStake,
    // );
    // expect(actualAmountInTokenAfterStake).to.be.eq(expectedAmountInTokenAfterStake);

    // 3. claim the reward token
    await this.testVaultHealer.testClaimRewardTokenCode(
      pool.pool,
      this.strategyMasterHealer.address,
      getOverrideOptions(),
    );
    // 3.1 assert whether the reward token's balance is as expected or not after claiming
    const actualRewardTokenBalanceAfterClaim = await this.testVaultHealer.getERC20TokenBalance(
      await this.strategyMasterHealer.getRewardToken(pool.pool),
      this.testVaultHealer.address,
    );
    const expectedRewardTokenBalanceAfterClaim = await farmRewardInstance.balanceOf(this.testVaultHealer.address);
    expect(actualRewardTokenBalanceAfterClaim).to.be.eq(expectedRewardTokenBalanceAfterClaim);

    // // 4. Swap the reward token into underlying token
    //COMMENTED OUT UNTIL SUFFICIENT LIQUIDITY IN WATCH FOR QUICKSWAP CALLS NOT TO REVERT
    // await this.testVaultHealer.testGetHarvestAllCodes(
    //   pool.pool,
    //   pool.tokens[0],
    //   this.strategyMasterHealer.address,
    //   getOverrideOptions(),
    // );
    // // 4.1 assert whether the reward token is swapped to underlying token or not
    // expect(await this.testVaultHealer.getERC20TokenBalance(pool.tokens[0], this.testVaultHealer.address)).to.be.gt(0);

    // 5. Unstake all staked lpTokens
    await this.testVaultHealer.testGetUnstakeAllCodes(
      pool.pool,
      this.strategyMasterHealer.address,
      getOverrideOptions(),
    );
    // 5.1 assert whether lpToken balance is as expected or not
    const actualLPTokenBalanceAfterUnstake = await this.strategyMasterHealer.getLiquidityPoolTokenBalance(
      this.testVaultHealer.address,
      this.testVaultHealer.address, // placeholder of type address
      pool.pool,
    );
    const expectedLPTokenBalanceAfterUnstake = await beefyDepositInstance.balanceOf(this.testVaultHealer.address);
    expect(actualLPTokenBalanceAfterUnstake).to.be.eq(expectedLPTokenBalanceAfterUnstake);
    // 5.2 assert whether staked lpToken balance is as expected or not
    const actualStakedLPTokenBalanceAfterUnstake = await this.strategyMasterHealer.getLiquidityPoolTokenBalanceStake(
      this.testVaultHealer.address,
      pool.pool,
    );
    const expectedStakedLPTokenBalanceAfterUnstake = await beefyStakingInstance.balanceOf(this.testVaultHealer.address);
    expect(actualStakedLPTokenBalanceAfterUnstake).to.be.eq(expectedStakedLPTokenBalanceAfterUnstake);
    // 6. Withdraw all lpToken balance
    await this.testVaultHealer.testGetWithdrawAllCodes(
      pool.tokens[0],
      pool.pool,
      this.strategyMasterHealer.address,
      getOverrideOptions(),
    );
    // 6.1 assert whether lpToken balance is as expected or not
    const actualLPTokenBalanceAfterWithdraw = await this.strategyMasterHealer.getLiquidityPoolTokenBalance(
      this.testVaultHealer.address,
      this.testVaultHealer.address, // placeholder of type address
      pool.pool,
    );
    const expectedLPTokenBalanceAfterWithdraw = await beefyDepositInstance.balanceOf(this.testVaultHealer.address);
    expect(actualLPTokenBalanceAfterWithdraw).to.be.eq(expectedLPTokenBalanceAfterWithdraw);
    // 6.2 assert whether underlying token balance is as expected or not after withdraw
    const actualUnderlyingTokenBalanceAfterWithdraw = await this.testVaultHealer.getERC20TokenBalance(
      (
        await this.strategyMasterHealer.getUnderlyingTokens(pool.pool, pool.pool)
      )[0],
      this.testVaultHealer.address,
    );
    const expectedUnderlyingTokenBalanceAfterWithdraw = await underlyingTokenInstance.balanceOf(
      this.testVaultHealer.address,
    );
    expect(actualUnderlyingTokenBalanceAfterWithdraw).to.be.eq(expectedUnderlyingTokenBalanceAfterWithdraw);
  });
}
