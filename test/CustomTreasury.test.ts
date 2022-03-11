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


describe(`CustomTreasury`, () => {
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

    describe("CustomTreasury - authorization", async () => {
        it("should revert if payoutToken address is zero", async () => {
            await expect( CustomTreasury.deploy(
                ZERO_ADDRESS,         //address _payoutToken,  todo - what should this be? we bond crystl and pay out in?
                user1.address,  //address _initialOwner
            )).to.be.reverted;
        });
        
        it("should revert if initialOwner address is zero", async () => {
            await expect( CustomTreasury.deploy(
                CRYSTL,         //address _payoutToken,  todo - what should this be? we bond crystl and pay out in?
                ZERO_ADDRESS,  //address _initialOwner
            )).to.be.reverted;
        });
        
        it("should revert if non-bond contract calls deposit()", async () => {
            await expect( customTreasury.deposit(
                CRYSTL,         //address _payoutToken,  todo - what should this be? we bond crystl and pay out in?
                100,            //address _initialOwner
                100
            )).to.be.reverted;
        });
        
        it("policy(initialOwner) address should be able to withdraw fund from treasury", async () => {
        
            let amount = "10000000000000000"; // 1 LP Token - 1000000000000000000 - 0xDE0B6B3A7640000
            // 185834149620404242644
            const actualTrueBondPrice = await customBond.trueBondPrice();
        
             await customBond
                .connect(user1)
                .deposit(amount, Number(actualTrueBondPrice) + 1, user1.address);
        
            expect(Array(await customBond.bondInfo(user1.address)).length).to.equal(1);
        
            const transferAmount = 1000;
            const balanceBefore = await LPtoken.balanceOf(user3.address);
        
            await customTreasury.withdraw(
                MATIC_CRYSTL_APE_LP,
                user3.address,
                transferAmount
            );
            
            const balanceAfter = await LPtoken.balanceOf(user3.address);
        
            expect(balanceAfter).to.equal(balanceBefore + transferAmount)
        
        });        
    });
});