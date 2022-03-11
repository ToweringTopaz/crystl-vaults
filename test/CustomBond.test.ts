import { ethers, network } from "hardhat";
import { BigNumber } from "ethers";
import { expect } from "chai";
import { tokens, accounts, lps, routers } from "../configs/addresses";
import { advanceBlock, advanceBlockTo, advanceBlockWithNumber, setBalance, increaseTime } from "./utils";
const { WMATIC, CRYSTL, DAI } = tokens.polygon;
const { MATIC_CRYSTL_APE_LP } = lps.polygon;
const { APESWAP_ROUTER } = routers.polygon;
const { FEE_ADDRESS, BURN_ADDRESS, ZERO_ADDRESS } = accounts.polygon;
import { IUniRouter02_abi } from './abi_files/IUniRouter02_abi';
import { token_abi } from './abi_files/token_abi';
import { IWETH_abi } from './abi_files/IWETH_abi';
import { Contract, ContractFactory, Signer } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
const { IUniswapV2Pair_abi } = require('./abi_files/IUniswapV2Pair_abi.js');


describe(`CustomBond`, () => {
    let LPtoken:Contract;
    let wmatic_token:Contract;
    let crystlToken:Contract;
    let crystlTokenTotalSupply: any;
    let crystlTokenDecimals: any;

    let user1:SignerWithAddress, user2:SignerWithAddress, user3:SignerWithAddress, _:SignerWithAddress;
        
    let CustomTreasury:ContractFactory;
    let customTreasury:Contract;

    let CustomBond:ContractFactory;
    let customBond:Contract;

    let vestingTerm = 46200; // 7 days
    let minimumPrice = 10000;
    let initialCV = 250000;
    let maxPayout = 5000;
    let maxDebt = "100000000000000000000000"; // 1e23
    let initialDebt = "690000000000000000000"; // 69e19
    let maxInt = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";

    before(async () => {
        [user1, user2, user3, _] = await ethers.getSigners();

        CustomTreasury = await ethers.getContractFactory("CustomTreasury");
        CustomBond = await ethers.getContractFactory("CustomBond");
    });

    beforeEach(async () => {
        customTreasury = await CustomTreasury.deploy(
            CRYSTL,         //address _payoutToken,  todo - what should this be? we bond crystl and pay out in?
            user1.address,  //address _initialOwner
        );
        customBond = await CustomBond.deploy(        
            customTreasury.address, //address _customTreasury, 
            MATIC_CRYSTL_APE_LP,    //address _principalToken, CRYSTL-CRO LP
            user1.address,          //address _initialOwner
        );
        // user1's balance of principal token is 457,342114826036968505
        
        await customTreasury.toggleBondContract(customBond.address);
        
        await customBond.setBondTerms(0, 46200); //PARAMETER = { 0: VESTING, 1: PAYOUT, 3: DEBT }

        await customBond.initializeBond(
            initialCV,                    //uint _controlVariable, 
            vestingTerm,                  //uint _vestingTerm, 7 days
            minimumPrice,                 //1351351, uint _minimumPrice,
            maxPayout,                    //uint _maxPayout, 100e9
            maxDebt,                      //uint _maxDebt, 
            initialDebt,                  //uint _initialDebt
        );

        // LPToken decimals : 18
        LPtoken = await ethers.getContractAt(IUniswapV2Pair_abi, MATIC_CRYSTL_APE_LP);

        await LPtoken.connect(user1).approve(customBond.address, maxInt);
        await LPtoken.connect(user2).approve(customBond.address, maxInt);

        const TOKEN0ADDRESS = await LPtoken.token0();
        const TOKEN1ADDRESS = await LPtoken.token1();
    
        const uniswapRouter = await ethers.getContractAt(IUniRouter02_abi, APESWAP_ROUTER);
        
        // set MATIC balance (10000 MATIC)
        await setBalance(user1.address, "0x21E19E0C9BAB2400000");
        // set MATIC balance (10000000 MATIC)
        await setBalance(user2.address, "0x84595161401484A000000");

        // fund the treasury with reward token, Crystl
        crystlToken = await ethers.getContractAt(token_abi, CRYSTL);
        // user 1 balance of CRYSTL is 457,342114826036968505

        crystlTokenTotalSupply = await crystlToken.totalSupply(); // 0x0a5c56a51123c165ccffed: 12525314,226888042533945325
        crystlTokenDecimals = await crystlToken.decimals(); // 18

        await uniswapRouter.connect(user2).swapExactETHForTokens(0, [WMATIC, CRYSTL], customTreasury.address, Date.now() + 900, { value: ethers.utils.parseEther("9900000") })
        
        if (TOKEN0ADDRESS == ethers.utils.getAddress(WMATIC)) {
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN0ADDRESS); 
            await wmatic_token.deposit({ value: ethers.utils.parseEther("4500") });

            await uniswapRouter.swapExactETHForTokens(0, [WMATIC, TOKEN1ADDRESS], user1.address, Date.now() + 900, { value: ethers.utils.parseEther("4500") })
        } else if(TOKEN1ADDRESS == ethers.utils.getAddress(WMATIC)) {
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN1ADDRESS); 
            await wmatic_token.deposit({ value: ethers.utils.parseEther("4500") });

            await uniswapRouter.swapExactETHForTokens(0, [WMATIC, TOKEN0ADDRESS], user1.address, Date.now() + 900, { value: ethers.utils.parseEther("4500") })
        }
 
        // Create instances of token0 and token1
        const token0 = await ethers.getContractAt(token_abi, TOKEN0ADDRESS);
        const token1 = await ethers.getContractAt(token_abi, TOKEN1ADDRESS);
        
        // user1 approves token to add liquidity to get LP tokens
        var token0BalanceUser1 = await token0.balanceOf(user1.address);
        await token0.approve(uniswapRouter.address, token0BalanceUser1);
        
        var token1BalanceUser1 = await token1.balanceOf(user1.address);
        await token1.approve(uniswapRouter.address, token1BalanceUser1);

        // Add Liquidity to get WMATIC-CRYSTL LP Tokens
        await uniswapRouter.addLiquidity(TOKEN0ADDRESS, TOKEN1ADDRESS, token0BalanceUser1, token1BalanceUser1, 0, 0, user1.address, Date.now() + 900);
    });

    describe(`Crystl CustomBond - market mechanism`, async () => {

        it("should revert if totalDebt exceed maxDebt", async () => {

            const maxDebt = "10000000000000000000"; // 1e20
            const newInitialDebt = "69000000000000000"; // 69e16
            const capacity = BigNumber.from(maxDebt).sub(newInitialDebt);

            let amount = "100000000000000000"; // 100 LP Token //100000000000000000000
                          
            const newCustomBond = await CustomBond.deploy(        
                customTreasury.address, //address _customTreasury, 
                MATIC_CRYSTL_APE_LP,    //address _principalToken, CRYSTL-CRO LP
                user1.address,          //address _initialOwner
            );

            await newCustomBond.setBondTerms(0, 46200); //PARAMETER = { 0: VESTING, 1: PAYOUT, 3: DEBT }

            await customTreasury.toggleBondContract(newCustomBond.address);

            await newCustomBond.initializeBond(
                initialCV,                    //uint _controlVariable, 
                vestingTerm,                  //uint _vestingTerm, 7 days
                minimumPrice,                 //1351351, uint _minimumPrice,
                100000,                       //uint _maxPayout, 100e9
                maxDebt,                         //uint _maxDebt, 
                newInitialDebt,                  //uint _initialDebt
            );

            await LPtoken.connect(user1).approve(newCustomBond.address, maxInt);

            let actualTrueBondPrice = await newCustomBond.trueBondPrice();
            // 0x0a12f7867cfcfcc8d4
            // 0x056233fed5440b0000

            // 185834149620404242644
            // 9310000000000000000000
            await newCustomBond
                .connect(user1)
                .deposit(capacity, Number(actualTrueBondPrice) + 1, user1.address);

            actualTrueBondPrice = await newCustomBond.trueBondPrice();

            // console.log("balance of LPToken :: ", await LPtoken.balanceOf(user1.address));

            await expect(newCustomBond
                .connect(user1)
                .deposit(amount, Number(actualTrueBondPrice) + 1, user1.address)).to.be.reverted;
        });

        describe("Market creation & variable settings", async () => {

            it("should create bond market", async () => {
                let [cv, , , ,] = await customBond.terms();
                expect(cv).to.not.equal(0);
            });
    
            it("should create market with correct market variables", async () => {
                const [cv, vesting, minimum, mPayout, mDebt] = await customBond.terms();
    
                expect(cv).to.equal(initialCV);
                expect(vesting).to.equal(vestingTerm);
                expect(minimum).to.equal(minimumPrice);
                expect(mPayout).to.equal(maxPayout);
                expect(mDebt).to.equal(maxDebt);
            });
            // **
            it("should be able to adjust vestingTerm with setBondTerms()", async () => {
                let [, initialVestingTerm, , ,] = await customBond.terms();
                expect(initialVestingTerm).to.equal(vestingTerm);
    
                await customBond.setBondTerms(0, 20000);
    
                let [, finalVestingTerm, , ,] = await customBond.terms();
                expect(finalVestingTerm).to.equal(20000);
            });
            // **
            it("should revert if vestingTerm is less than 36 hours (1000 blocks)", async () => {
                let [, initialVestingTerm, , ,] = await customBond.terms();
                expect(initialVestingTerm).to.equal(vestingTerm);
    
                await expect(customBond.setBondTerms(0, 500)).to.be.reverted;
            });
    
            it("should be able to adjust maxPayout with setBondTerms()", async () => {
                let [, , , initialMaxPayout,] = await customBond.terms();
                expect(initialMaxPayout).to.equal(maxPayout);
    
                await customBond.setBondTerms(1, 100);
    
                let [, , , finalMaxPayout,] = await customBond.terms();
                expect(finalMaxPayout).to.equal(100);
            });
    
            it("should revert if maxPayout is above 1 percent", async () => {
                let [, , , initialMaxPayout,] = await customBond.terms();
                expect(initialMaxPayout).to.equal(maxPayout);
    
                await expect(customBond.setBondTerms(1, 1000e9)).to.be.reverted;
            });
    
            it("should be able to adjust maxDebt with setBondTerms()", async () => {
                let [, , , , initialMaxDebt] = await customBond.terms();
                expect(initialMaxDebt).to.equal(maxDebt);
    
                await customBond.setBondTerms(2, 1000e9);
    
                let [, , , , MaxDebt] = await customBond.terms();
    
                expect(MaxDebt).to.equal(1000e9);
    
                await customBond.setBondTerms(2, 20000e9);
    
                let [, , , , finalMaxDebt] = await customBond.terms();
    
                expect(finalMaxDebt).to.equal(20000e9);
            });
    
            it("should revert if customTreasury is zeroAddress", async () => {
                await expect(CustomBond.deploy(        
                    ZERO_ADDRESS,           //address _customTreasury, 
                    MATIC_CRYSTL_APE_LP,    //address _principalToken, CRYSTL-CRO LP
                    user1.address,          //address _initialOwner
                )).to.be.reverted;
            });
    
            it("should revert if principalToken is zeroAddress", async () => {
                await expect(CustomBond.deploy(        
                    customTreasury.address,           //address _customTreasury, 
                    ZERO_ADDRESS,    //address _principalToken, CRYSTL-CRO LP
                    user1.address,          //address _initialOwner
                )).to.be.reverted;
            });
    
            it("should revert if initialOwner is zeroAddress", async () => {
                await expect(CustomBond.deploy(        
                    customTreasury.address,           //address _customTreasury, 
                    MATIC_CRYSTL_APE_LP,    //address _principalToken, CRYSTL-CRO LP
                    ZERO_ADDRESS,          //address _initialOwner
                )).to.be.reverted;
            });
    
            // it("should close market in correct amount of time", async () => {
            //     // quite ambiguous
            //     // lastest version has market conclusion time.
            //     // however, customBond.sol doesn't seem to have one
            // });
    
            it("should revert if currentDebt is not zero when initializeBond() is called", async () => {
                await expect(
                    customBond.initializeBond(
                        initialCV,
                        vestingTerm,
                        minimumPrice,
                        maxPayout,
                        maxDebt,
                        initialDebt
                    )
                ).to.be.reverted
            });

            it("should start with expected price at market creation (Actual Price)", async () => {
                const currentDebt = initialDebt;
    
                const debtRatio = BigNumber.from(currentDebt).mul(BigNumber.from("0x"+(1e18).toString(16))).div(BigNumber.from(crystlTokenTotalSupply));
    
                // CV * debtRatio / 1e13
                const expectedBondPrice = BigNumber.from(initialCV).mul(debtRatio).div(BigNumber.from(10 ** (crystlTokenDecimals-5))); 
                
                // 1377211
                const expectedTrueBondPrice = expectedBondPrice.add(expectedBondPrice.div("0x"+(1e6).toString(16)));
                // 1375833.789
                const lowerBound = Number(expectedTrueBondPrice) * 0.999;
    
                // 1377033
                const actualTrueBondPrice = await customBond.trueBondPrice();
    
                expect(Number(actualTrueBondPrice)).to.be.greaterThan(lowerBound);
            });
        });

        describe("BondPrice & deposit", async () => {
            it("should set bondPrice correctly", async () => {
                const currentDebt = initialDebt;
    
                const debtRatio = BigNumber.from(currentDebt).mul(BigNumber.from("0x"+(1e18).toString(16))).div(BigNumber.from(crystlTokenTotalSupply));
    
                // CV * debtRatio / 1e13
                const expectedBondPrice = BigNumber.from(initialCV).mul(debtRatio).div(BigNumber.from(10 ** (crystlTokenDecimals-5))); 
                
                const lowerBound = Number(expectedBondPrice) * 0.999;
                expect(Number(await customBond.bondPrice())).to.be.greaterThan(lowerBound);
                
                const upperBound = Number(expectedBondPrice) * 1.001;
                expect(Number(await customBond.bondPrice())).to.be.lessThan(upperBound);
            });
    
            // the lastet version of Bonding contract uses block.timestamp for time calculation.
            // however, this version uses block.number for time.
            // so advancing block rather than time is the right option
            it("should decrease totalDebt linearly if no deposit", async () => {
                const initialTotalDebt = await customBond.currentDebt();
    
                await advanceBlockWithNumber(5760); // 1 day
    
                const currentDecayDebt = await customBond.currentDebt();
    
                expect(Number(initialTotalDebt)).to.be.greaterThan(Number(currentDecayDebt));
            });

            it("should return minimum price if bondPrice gets lower than minimumPrice", async () => {
                await advanceBlockWithNumber(vestingTerm);
    
                const rMinimumPrice = await customBond.bondPrice();
    
                expect(Number(rMinimumPrice)).to.equal(minimumPrice);
            });
    
            it("should purchase bond with minimum price if bondPrice gets lower than minimumPrice", async () => {
                await advanceBlockWithNumber(vestingTerm);
    
                let amount = "10000000000000000"; // 1 LP Token - 1000000000000000000 - 0xDE0B6B3A7640000
    
                const actualTrueBondPrice = await customBond.trueBondPrice();
    
                const payout = await customBond.payoutFor(amount);
                const expectedPayout = Number(amount) / minimumPrice * 0.999;
    
                expect(Number(payout)).to.be.greaterThan(Number(expectedPayout));
                expect(await customBond.percentVestedFor(user1.address)).to.equal(0);
    
                const blockNumber = await ethers.provider.getBlockNumber();
    
                await expect(customBond
                        .connect(user1)
                        .deposit(amount, Number(actualTrueBondPrice) + 1, user1.address))
                        .to.emit(customBond, "BondCreated").withArgs(amount, payout, blockNumber + vestingTerm + 1);
            });
    
            it("should payout correct amount of payoutToken for bondPrice", async () => {
                const actualTrueBondPrice = await customBond.trueBondPrice(); // 1,377,033
                const bondPrice = await customBond.bondPrice();
                // console.log("bondPrice :: ", bondPrice); // 1376972
    
                const amount = "10000000000000000"; // 10,000 LP Token // 10000000000000000 -> 1 LP Token
                const expectedPayout = Number(amount) / Number(bondPrice) * 1e7;
                // console.log("expectedPayout :: ", expectedPayout); // 7262311797189776
                let lowerBound = expectedPayout * 0.999;
                let upperBound = expectedPayout * 1.001;
    
                expect(Number(await customBond.payoutFor(amount))).to.be.greaterThan(lowerBound);
                expect(Number(await customBond.payoutFor(amount))).to.be.lessThan(upperBound);
    
            });
    
            it("should allow a deposit", async () => {
                let amount = "10000000000000000"; // 1 LP Token - 1000000000000000000 - 0xDE0B6B3A7640000
                         // 185834149620404242644
                const actualTrueBondPrice = await customBond.trueBondPrice();
    
                await customBond
                    .connect(user1)
                    .deposit(amount, Number(actualTrueBondPrice) + 1, user1.address);
                
                expect(Array(await customBond.bondInfo(user1.address)).length).to.equal(1);
            });   
    
            it("should not allow a deposit greater than max payout", async () => {   
                const mPayout = await customBond.maxPayout();    
                //console.log("mPayout : ", mPayout.toString());     
    
                const actualTrueBondPrice = await customBond.trueBondPrice();
                let maxAmount = actualTrueBondPrice * maxPayout;
                let mAmount = BigNumber.from(maxAmount.toString());
                const payoutFor = await customBond.payoutFor(mAmount);    
    
                await expect(customBond
                    .connect(user1)
                    .deposit(mPayout, Number(actualTrueBondPrice) + 1, user1.address)).to.be.reverted;
                
            });
    
            it("should revert if bond is too small", async () => {
                const actualTrueBondPrice = await customBond.trueBondPrice();
                const maxAmount = actualTrueBondPrice * maxPayout;
    
                await expect(customBond
                    .connect(user1)
                    .deposit(10, Number(actualTrueBondPrice) + 1, user1.address)).to.be.reverted;
            });
    
            it("should revert if bond is too big", async () => {
                const actualTrueBondPrice = await customBond.trueBondPrice();
                const maxAmount = actualTrueBondPrice * maxPayout;
    
                await expect(customBond
                    .connect(user1)
                    .deposit(10000000000e18, Number(actualTrueBondPrice) + 1, user1.address)).to.be.reverted;
            });
    
            it("should revert if actual bond price is higher than maxPrice", async () => {
                let amount = "10000000000000000"; // 1 LP Token - 1000000000000000000 - 0xDE0B6B3A7640000
        
                await expect(customBond
                    .connect(user1)
                    .deposit(amount, 100, user1.address)).to.be.reverted;
            });
    
    
            it("should revert if depositor address is ZERO_ADDRESS", async () => {
                const actualTrueBondPrice = await customBond.trueBondPrice();
                let amount = "10000000000000000"; // 1 LP Token - 1000000000000000000 - 0xDE0B6B3A7640000
    
                await expect(customBond
                    .connect(user1)
                    .deposit(amount, Number(actualTrueBondPrice) - 1000, ZERO_ADDRESS)).to.be.reverted;
            });
        });

        describe("Adjustments", async () => {
            it("should be able to start adjustment if behind schedule", async () => {
                const amount = "200000000000000000"; // 0.2 LP Token
    
                const maxPrice = await customBond.trueBondPrice() + 100;
    
                const isAddition = false;
                const incrementRate = initialCV / 50; // 2% decrement every deposit through adjust()
                const target = initialCV - (initialCV / 10); // target CV : 90% of current CV
                const buffer = 0;
    
                
                await customBond.deposit(amount, maxPrice, user1.address);
    
                await advanceBlockWithNumber(vestingTerm / 2); // vestingTerm
    
                const lastBlock = await ethers.provider.getBlockNumber();
    
                await customBond.setAdjustment(
                    isAddition,
                    incrementRate,
                    target,
                    buffer
                );
    
                const [rIsAddition, rIncrementRate, rTarget, rBuffer, rLastBlock] = await customBond.adjustment();
    
                expect(rIsAddition).to.equal(isAddition);
                expect(rIncrementRate).to.equal(incrementRate);
                expect(rTarget).to.equal(target);
                expect(rBuffer).to.equal(buffer);
                expect(rLastBlock).to.equal(lastBlock + 1);
    
                await expect(
                    customBond.deposit(amount, maxPrice, user2.address)
                ).to.emit(customBond, "ControlVariableAdjustment").withArgs(initialCV, 
                                                                            initialCV - incrementRate, 
                                                                            incrementRate, 
                                                                            isAddition);
    
                const [cv, , , , ] = await customBond.terms();
                expect(Number(cv)).to.equal(initialCV - incrementRate);
    
                await customBond.deposit(amount, maxPrice, user2.address);
    
                for (let i = 0; i < 4; i++) {
                    await customBond.deposit(amount, maxPrice, user2.address);
                }
    
                // After 5 times of adjustment, CV gets even with target as IncrementRate=2% , target=90%
                const [finalCV, , , , ] = await customBond.terms();
                expect(finalCV).to.equal(target);
    
                // After cv reaches the target, increment is set to zero
                const [, fIncrementRate, , , ] = await customBond.adjustment();
                expect(fIncrementRate).to.equal(0);
            });
    
            it("should be able to start adjustment if ahead of schedule", async () => {
                const amount = "200000000000000000"; // 0.2 LP Token
    
                const maxPrice = await customBond.trueBondPrice() + 100;
    
                const isAddition = true;
                const incrementRate = initialCV / 50; // 2% decrement every deposit through adjust()
                const target = initialCV + (initialCV / 10); // target CV : 90% of current CV
                const buffer = 0;
    
                
                await customBond.deposit(amount, maxPrice, user1.address);
    
                await advanceBlockWithNumber(vestingTerm / 2); // vestingTerm
    
                const lastBlock = await ethers.provider.getBlockNumber();
    
                await customBond.setAdjustment(
                    isAddition,
                    incrementRate,
                    target,
                    buffer
                );
    
                const [rIsAddition, rIncrementRate, rTarget, rBuffer, rLastBlock] = await customBond.adjustment();
    
                expect(rIsAddition).to.equal(isAddition);
                expect(rIncrementRate).to.equal(incrementRate);
                expect(rTarget).to.equal(target);
                expect(rBuffer).to.equal(buffer);
                expect(rLastBlock).to.equal(lastBlock + 1);
    
                await expect(
                    customBond.deposit(amount, maxPrice, user1.address)
                ).to.emit(customBond, "ControlVariableAdjustment").withArgs(initialCV, 
                                                                            initialCV + incrementRate, 
                                                                            incrementRate, 
                                                                            isAddition);
    
                const [cv, , , , ] = await customBond.terms();
                expect(Number(cv)).to.equal(initialCV + incrementRate);
                
                for (let i = 0; i < 4; i++) {
                    await customBond.deposit(amount, maxPrice, user2.address);
                }
    
                // After 5 times of adjustment, CV gets even with target as IncrementRate=2% , target=90%
                const [finalCV, , , , ] = await customBond.terms();
                expect(finalCV).to.equal(target);
    
                // After cv reaches the target, increment is set to zero
                const [, fIncrementRate, , , ] = await customBond.adjustment();
                expect(fIncrementRate).to.equal(0);
            });
    
            it("should revert if non-policy address tries to set adjustment", async () => {
                const isAddition = false;
                const incrementRate = initialCV / 50; // 2% decrement every deposit through adjust()
                const target = initialCV - (initialCV / 10); // target CV : 90% of current CV
                const buffer = 0;
    
                await expect(
                    customBond.connect(user2).setAdjustment(
                    isAddition,
                    incrementRate,
                    target,
                    buffer
                )).to.be.reverted
            });
    
            it("should revert if adjustment tries to increase CV for over 3% at once(incrementRate)", async () => {
                const isAddition = true;
                const incrementRate = initialCV / 10; // 10% decrement every deposit through adjust()
                const target = initialCV + (initialCV / 10); // target CV : 90% of current CV
                const buffer = 0;
    
                await expect(
                    customBond.setAdjustment(
                    isAddition,
                    incrementRate,
                    target,
                    buffer
                )).to.be.reverted
            });
    
            it("should revert if adjustment tries to decrease CV for over 3% at once(incrementRate)", async () => {
                const isAddition = false;
                const incrementRate = initialCV / 10; // 10% decrement every deposit through adjust()
                const target = initialCV - (initialCV / 10); // target CV : 90% of current CV
                const buffer = 0;
    
                await expect(
                    customBond.setAdjustment(
                    isAddition,
                    incrementRate,
                    target,
                    buffer
                )).to.be.reverted
            });
        });

        describe("Vesting Period", async () => {
            it("pendingPayout should increase linearly as time passes in vesting period", async () => {
                let amount = "10000000000000000"; // 1 LP Token - 1000000000000000000 - 0xDE0B6B3A7640000
                // 185834149620404242644
                const actualTrueBondPrice = await customBond.trueBondPrice();
    
                const payout = await customBond.payoutFor(amount);
                const expectedPayout = Number(payout) / 2 * 0.999;
    
                await customBond
                        .connect(user1)
                        .deposit(amount, Number(actualTrueBondPrice) + 1, user1.address);
    
                const initialPendingPayout = await customBond.pendingPayoutFor(user1.address);
    
                expect(initialPendingPayout).to.equal(0);
    
                await advanceBlockWithNumber(vestingTerm / 2);
    
                const finalPendingPayout = await customBond.pendingPayoutFor(user1.address);
    
                expect(Number(finalPendingPayout)).to.be.greaterThan(expectedPayout);
            });
    
            it("should redeem all amount of payout after vesting period", async () => {
                let amount = "10000000000000000"; // 1 LP Token - 1000000000000000000 - 0xDE0B6B3A7640000
                // 185834149620404242644
                const actualTrueBondPrice = await customBond.trueBondPrice();
    
                const payout = await customBond.payoutFor(amount);

                const lowerBound = Number(payout) * 0.999;
                const upperBound = Number(payout) * 1.001;

                
                await customBond
                        .connect(user1)
                        .deposit(amount, Number(actualTrueBondPrice) + 1, user1.address);
                
                await advanceBlockWithNumber(vestingTerm);
    
                const finalPendingPayout = await customBond.pendingPayoutFor(user1.address);
    
                const balanceBeforeRedeem = await crystlToken.balanceOf(user1.address);

                
                await customBond.connect(user1).redeem(user1.address);
    
                const balanceAfterRedeem = await crystlToken.balanceOf(user1.address);

                expect(Number(balanceAfterRedeem)).to.be.greaterThan(lowerBound);
                expect(Number(balanceAfterRedeem)).to.be.lessThan(upperBound);
    
                expect(Number(finalPendingPayout)).to.be.greaterThan(lowerBound);
                expect(Number(finalPendingPayout)).to.be.lessThan(upperBound);
    
            });
    
            it("should return accurate amount of vesting period percentage", async () => {
                let amount = "10000000000000000"; // 1 LP Token - 1000000000000000000 - 0xDE0B6B3A7640000
                // 185834149620404242644
                const actualTrueBondPrice = await customBond.trueBondPrice();
    
                const payout = await customBond.payoutFor(amount);
                const expectedPayout = Number(payout) * 0.999;
    
                expect(await customBond.percentVestedFor(user1.address)).to.equal(0);
    
                await customBond
                        .connect(user1)
                        .deposit(amount, Number(actualTrueBondPrice) + 1, user1.address);
                
                const initialPercent = await customBond.percentVestedFor(user1.address);      
    
                expect(initialPercent).to.equal(0);
    
                await advanceBlockWithNumber(vestingTerm);
    
                const finalPercent = await customBond.percentVestedFor(user1.address);      
    
                expect(finalPercent).to.equal(10000);
            });
            it("should redeem linearly during the vesting period", async () => {
                let amount = "10000000000000000"; // 1 LP Token - 1000000000000000000 - 0xDE0B6B3A7640000
    
                const actualTrueBondPrice = await customBond.trueBondPrice();
                const payout = await customBond.payoutFor(amount);
    
                await expect(customBond
                        .connect(user1)
                        .deposit(amount, Number(actualTrueBondPrice) + 1, user1.address));
                
                
                await advanceBlockWithNumber(vestingTerm / 2);
                
                const balanceBefore = await crystlToken.balanceOf(user1.address);
    
                await customBond.redeem(user1.address);
    
                const balance = await crystlToken.balanceOf(user1.address);
    
                const balanceLowerBound = Number(payout / 2) * 0.999;
                const balanceUpperBound = Number(payout / 2) * 1.001;
    
                expect(Number(balance - balanceBefore)).to.be.greaterThan(balanceLowerBound);
                expect(Number(balance - balanceBefore)).to.be.lessThan(balanceUpperBound);
            });
    
            it("should redeem all amount after vesting period", async () => {
                let amount = "10000000000000000"; // 1 LP Token - 1000000000000000000 - 0xDE0B6B3A7640000
    
                const actualTrueBondPrice = await customBond.trueBondPrice();
                const payout = await customBond.payoutFor(amount);
    
                const balanceBefore = await crystlToken.balanceOf(user1.address);
    
                await expect(customBond
                        .connect(user1)
                        .deposit(amount, Number(actualTrueBondPrice) + 1, user1.address));
    
                await advanceBlockWithNumber(vestingTerm+10);
    
                expect(Number(await customBond.percentVestedFor(user1.address))).to.be.greaterThanOrEqual(10000);
    
                await customBond.redeem(user1.address);
    
                const balance = await crystlToken.balanceOf(user1.address);
                const balanceLowerBound = Number(payout) * 0.999;
                const balanceUpperBound = Number(payout) * 1.001;
    
                expect(Number(balance)).to.be.greaterThan(balanceLowerBound + Number(balanceBefore));
                expect(Number(balance)).to.be.lessThan(balanceUpperBound + Number(balanceBefore));
            });
    
        });
    });
});
