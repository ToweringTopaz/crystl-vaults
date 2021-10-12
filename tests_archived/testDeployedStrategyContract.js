// import hre from "hardhat";

const { tokens } = require('../configs/addresses.js');
const { WMATIC, CRYSTL, DAI, WETH } = tokens.polygon;
const { expect } = require('chai');
const { ethers } = require('hardhat');
const { IUniRouter02_abi } = require('./IUniRouter02_abi.js');
const { token_abi } = require('./token_abi.js');
const { vaultHealer_abi } = require('./vaultHealer_abi.js'); //TODO - this would have to change if we change the vaulthealer
const { IWETH_abi } = require('./IWETH_abi.js');
const { IMasterchef_abi } = require('./IMasterchef_abi.js');
const { IUniswapV2Pair_abi } = require('./IUniswapV2Pair_abi.js');
const { deployed_contract_abi } = require('./deployed_contract_abi.js');


const withdrawFeeFactor = ethers.BigNumber.from(9990); //hardcoded for now - TODO change to pull from contract?
const WITHDRAW_FEE_FACTOR_MAX = ethers.BigNumber.from(10000); //hardcoded for now - TODO change to pull from contract?

//////////////////////////////////////////////////////////////////////////
// THESE FIVE VARIABLES BELOW NEED TO BE SET CORRECTLY FOR A GIVEN TEST //
//////////////////////////////////////////////////////////////////////////

const deployed_contract_address = "0xA6Ee9b6d8d0853614257297BF140fcD3200394fC";

describe(`Testing deployed contract at address ${deployed_contract_address}` , () => {
    before(async () => {
        [owner, addr1, addr2, _] = await ethers.getSigners();
        console.log("Fetched account signers")

        strategyMasterHealer = await ethers.getContractAt(deployed_contract_abi, deployed_contract_address);
        console.log("Strategy contract deployed");
        
        TOKEN0 = await strategyMasterHealer.token0Address(); 
        TOKEN1 = await strategyMasterHealer.token1Address(); 
        VAULT_HEALER = await strategyMasterHealer.vaultChefAddress();

        vaultHealer = await ethers.getContractAt(vaultHealer_abi, VAULT_HEALER);
        vaultHealerOwner = await vaultHealer.owner();
        console.log("Fetched VaultHealer contract and owner");

        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [vaultHealerOwner],
          });
        
        vaultHealerOwnerSigner = await ethers.getSigner(vaultHealerOwner)

        // await vaultHealer.connect(vaultHealerOwnerSigner).addPool(strategyMasterHealer.address);
        console.log("Added pool to VaultHealer");

        await network.provider.send("hardhat_setBalance", [
            owner.address,
            "0x3635c9adc5dea00000", //amount of 1000 in hex
        ]);
        console.log("Funded main address with 1000 MATIC")
        const ROUTER = await strategyMasterHealer.uniRouterAddress();
        uniswapRouter = await ethers.getContractAt(IUniRouter02_abi, ROUTER);
        console.log("Fetched Router instance");

        if (TOKEN0 == ethers.utils.getAddress(WMATIC) ){
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN0); 
            await wmatic_token.deposit({ value: ethers.utils.parseEther("100") });
        } else {
            await uniswapRouter.swapExactETHForTokens(0, [WMATIC, WETH, TOKEN0], owner.address, Date.now() + 900, { value: ethers.utils.parseEther("100") })
        }
        console.log("Swapped MATIC for token0")

        if (TOKEN1 == ethers.utils.getAddress(WMATIC)) {
            wmatic_token = await ethers.getContractAt(IWETH_abi, TOKEN1); 
            await wmatic_token.deposit({ value: ethers.utils.parseEther("100") });
        } else {
            await uniswapRouter.swapExactETHForTokens(0, [WMATIC, TOKEN1], owner.address, Date.now() + 900, { value: ethers.utils.parseEther("100") })
        }
        console.log("Swapped MATIC for token1")

    });

    describe(`Testing deployment:
    `, () => {
        // it('Should set the pid such that our want tokens correspond with the masterchef pools LP tokens', async () => {
        //     masterchef = await ethers.getContractAt(IMasterchef_abi, MASTERCHEF); 
        //     poolInfo = await masterchef.poolInfo(PID);
        //     lpToken = poolInfo[0];
        //     expect(lpToken).to.equal(ethers.utils.getAddress(LIQUIDITY_POOL));
        // })

        it(`Should set tolerance in the range of 1-3
        `, async () => { 
            expect(await strategyMasterHealer.tolerance()).to.be.within(1,3);
        })
        //and paths too?
    })

    describe(`Testing depositing into vault, compounding vault, withdrawing from vault:
    `, () => {
        // Create LPs for the vault
        it('Should create the right LP tokens for user to deposit in the vault', async () => {
            token0 = await ethers.getContractAt(token_abi, TOKEN0);
            var token0Balance = await token0.balanceOf(owner.address);
            await token0.approve(uniswapRouter.address, token0Balance);

            token1 = await ethers.getContractAt(token_abi, TOKEN1);
            var token1Balance = await token1.balanceOf(owner.address);
            await token1.approve(uniswapRouter.address, token1Balance);

            await uniswapRouter.addLiquidity(TOKEN0, TOKEN1, token0Balance, token1Balance, 0, 0, owner.address, Date.now() + 900)
            const LIQUIDITY_POOL = await strategyMasterHealer.wantAddress();
            LPtoken = await ethers.getContractAt(IUniswapV2Pair_abi, LIQUIDITY_POOL);
            initialLPtokenBalance = await LPtoken.balanceOf(owner.address);
            expect(initialLPtokenBalance).to.not.equal(0);
        })
        
        // Stake a round number of LPs (e.g., 1 or 0.0001) - not a round number yet!
        it('Should deposit users whole balance of LP tokens into the vault, increasing vaultSharesTotal by the correct amount', async () => {
            await LPtoken.approve(vaultHealer.address, initialLPtokenBalance); //no, I have to approve the vaulthealer surely?
            
            poolLength = await vaultHealer.poolLength()
            const LPtokenBalanceBeforeFirstDeposit = await LPtoken.balanceOf(owner.address);

            await vaultHealer["deposit(uint256,uint256)"](poolLength-1,initialLPtokenBalance); //owner (default signer) deposits 1 of LP tokens into pid 0 of vaulthealer
            const vaultSharesTotalAfterFirstDeposit = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0

            expect(LPtokenBalanceBeforeFirstDeposit).to.equal(vaultSharesTotalAfterFirstDeposit); //will this work for 2nd deposit? on normal masterchef?
        })
        
        // Compound LPs (Call the earnSome function with this specific farm’s pid).
        // Check balance to ensure it increased as expected
        it('Should wait 100 blocks, then compound the LPs by calling earnSome(), so that vaultSharesTotal is greater after than before', async () => {
            const vaultSharesTotalBeforeCallingEarnSome = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal()
            crystlToken = await ethers.getContractAt(token_abi, CRYSTL);
            daiToken = await ethers.getContractAt(token_abi, DAI);

            balanceCrystlAtBurnAddressBeforeEarn = await crystlToken.balanceOf("0x000000000000000000000000000000000000dEaD");
            balanceMaticAtUserAddressBeforeEarn = await owner.getBalance(); //maticToken.balanceOf(owner.address); //CHANGE THIS

            balanceDaiAtFeeAddressBeforeEarn = await daiToken.balanceOf("0x5386881b46C37CdD30A748f7771CF95D7B213637");
            balanceCrystlAtFeeAddressBeforeEarn = await crystlToken.balanceOf("0x5386881b46C37CdD30A748f7771CF95D7B213637");
            
            for (i=0; i<100;i++) {
                await ethers.provider.send("evm_mine"); //creates a 10 block delay
            }

            await vaultHealer.earnSome([poolLength-1]);
            
            vaultSharesTotalAfterCallingEarnSome = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal()

            const differenceInVaultSharesTotal = vaultSharesTotalAfterCallingEarnSome.sub(vaultSharesTotalBeforeCallingEarnSome);

            expect(differenceInVaultSharesTotal.toNumber()).to.be.gt(0);
        })
        
        // follow the flow of funds in the transaction to ensure burn, compound fee, and LP creation are all accurate.
        it('Should burn a small amount of CRYSTL with each earn, resulting in a small increase in the CRYSTL balance of the burn address', async () => {
            const balanceCrystlAtBurnAddressAfterEarn = await crystlToken.balanceOf("0x000000000000000000000000000000000000dEaD");
            expect(balanceCrystlAtBurnAddressAfterEarn).to.be.gt(balanceCrystlAtBurnAddressBeforeEarn);
        })

        // will redesign this test once we change the payout to WMATIC - at the moment it's tricky to see the increase in user's matic balance, as they also pay out gas
        // it('Should pay a small amount of MATIC to the user with each earn, resulting in a small increase in the MATIC balance of the user', async () => {
        //     const balanceMaticAtUserAddressAfterEarn = await owner.getBalance();
        //     console.log(balanceMaticAtUserAddressBeforeEarn);
        //     console.log(balanceMaticAtUserAddressAfterEarn);
        //     expect(balanceMaticAtUserAddressAfterEarn).to.be.gt(balanceMaticAtUserAddressBeforeEarn);        
        // }) 

        it('Should pay a small amount to the rewardAddress with each earn, resulting in a small increase in CRYSTL or DAI balance of the rewardAddress', async () => {
            const balanceCrystlAtFeeAddressAfterEarn = await crystlToken.balanceOf("0x5386881b46C37CdD30A748f7771CF95D7B213637");
            const balanceDaiAtFeeAddressAfterEarn = await daiToken.balanceOf("0x5386881b46C37CdD30A748f7771CF95D7B213637");
            expect(balanceCrystlAtFeeAddressAfterEarn.add(balanceDaiAtFeeAddressAfterEarn)).to.be.gt(balanceCrystlAtFeeAddressBeforeEarn.add(balanceDaiAtFeeAddressBeforeEarn));
        })
        
        // Unstake 50% of LPs. 
        // Check transaction to ensure withdraw fee amount is as expected and amount withdrawn in as expected
        it('Should delay 10 blocks, then unstake 50% of LPs with correct withdraw fee amount (0.1%) and decrease users stakedWantTokens balance correctly', async () => {
            for (i=0; i<10;i++) {
                await ethers.provider.send("evm_mine"); //creates a 10 block delay
            }
            
            const LPtokenBalanceBeforeFirstWithdrawal = await LPtoken.balanceOf(owner.address);
            const UsersStakedTokensBeforeFirstWithdrawal = await vaultHealer.stakedWantTokens(poolLength-1, owner.address);
            
            await vaultHealer["withdraw(uint256,uint256)"](poolLength-1, UsersStakedTokensBeforeFirstWithdrawal.div(2)); 
            
            const LPtokenBalanceAfterFirstWithdrawal = await LPtoken.balanceOf(owner.address);
            const vaultSharesTotalAfterFirstWithdrawal = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal() 

            expect(LPtokenBalanceAfterFirstWithdrawal.sub(LPtokenBalanceBeforeFirstWithdrawal))
            .to.equal(
                (vaultSharesTotalAfterCallingEarnSome.sub(vaultSharesTotalAfterFirstWithdrawal))
                .sub((WITHDRAW_FEE_FACTOR_MAX.sub(withdrawFeeFactor)).mul(vaultSharesTotalAfterCallingEarnSome.sub(vaultSharesTotalAfterFirstWithdrawal)).div(WITHDRAW_FEE_FACTOR_MAX))
                );
        })
        
        // Deposit 100% of users LP tokens into vault, ensure balance increases as expected.
        it('Should delay 10 blocks, then accurately increase vaultSharesTotal upon second deposit', async () => {
            for (i=0; i<10;i++) {
                await ethers.provider.send("evm_mine"); //creates a 10 block delay
            }
            
            await LPtoken.approve(vaultHealer.address, initialLPtokenBalance);
            const LPtokenBalanceBeforeSecondDeposit = await LPtoken.balanceOf(owner.address);
            const vaultSharesTotalBeforeSecondDeposit = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0

            await vaultHealer["deposit(uint256,uint256)"](poolLength-1, LPtokenBalanceBeforeSecondDeposit); //owner (default signer) deposits LP tokens into specified pid vaulthealer
            
            const LPtokenBalanceAfterSecondDeposit = await LPtoken.balanceOf(owner.address);
            const vaultSharesTotalAfterSecondDeposit = await strategyMasterHealer.connect(vaultHealerOwnerSigner).vaultSharesTotal() //=0;

            expect(LPtokenBalanceBeforeSecondDeposit.sub(LPtokenBalanceAfterSecondDeposit)).to.equal(vaultSharesTotalAfterSecondDeposit.sub(vaultSharesTotalBeforeSecondDeposit)); //will this work for 2nd deposit? on normal masterchef?
        })
        
        // Withdraw 100%
        it('Should withdraw remaining balance back to owner, minus withdrawal fee (0.1%)', async () => {
            for (i=0; i<10;i++) {
                await ethers.provider.send("evm_mine"); //creates a 10 block delay
            }
            
            const LPtokenBalanceBeforeFinalWithdrawal = await LPtoken.balanceOf(owner.address);
            const UsersStakedTokensBeforeFinalWithdrawal = await vaultHealer.stakedWantTokens(poolLength-1, owner.address);

            await vaultHealer["withdraw(uint256,uint256)"](poolLength-1, UsersStakedTokensBeforeFinalWithdrawal); //owner (default signer) deposits 1 of LP tokens into pid 0 of vaulthealer
            
            const LPtokenBalanceAfterFinalWithdrawal = await LPtoken.balanceOf(owner.address);
            UsersStakedTokensAfterFinalWithdrawal = await vaultHealer.stakedWantTokens(poolLength-1, owner.address);

            expect(LPtokenBalanceAfterFinalWithdrawal.sub(LPtokenBalanceBeforeFinalWithdrawal))
            .to.equal(
                (UsersStakedTokensBeforeFinalWithdrawal.sub(UsersStakedTokensAfterFinalWithdrawal))
                .sub(
                    (WITHDRAW_FEE_FACTOR_MAX.sub(withdrawFeeFactor))
                    .mul(UsersStakedTokensBeforeFinalWithdrawal.sub(UsersStakedTokensAfterFinalWithdrawal))
                    .div(WITHDRAW_FEE_FACTOR_MAX)
                ));
        })

        //ensure no funds left in the vault.
        it('Should leave zero funds in vault after 100% withdrawal', async () => {
            expect(UsersStakedTokensAfterFinalWithdrawal.toNumber()).to.equal(0);
        })
        
    })
})
