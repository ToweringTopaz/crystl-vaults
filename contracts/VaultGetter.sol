// SPDX-License-Identifier: GPL
pragma solidity ^0.8.10;

import "./VaultHealer.sol"; // polygon: 0xd4d696ad5a7779f4d3a0fc1361adf46ec51c632d
import "./libs/IUniPair.sol";
import "./libs/IMasterchef.sol";
uint constant GAS_FACTOR = 200000;

interface IPriceGetter { //polygon: 0x05D6C73D7de6E02B3f57677f849843c03320681c
    function getLPPrice(address,uint) external view returns (uint);
}

contract VaultGetter {

    struct VaultFacts {
        //these are immutable and so are stored here in this contract
        uint16 vaultPid;
        uint16 chefPid;
        uint8 tolerance;
        address masterchefAddress;
        address wantAddress;
        address strategyAddress;
        address token0Address;
        address token1Address;
        address lpFactoryAddress;
    }
    struct VaultInfo {
        bool paused;
        uint wantLockedTotal;
        uint burnedAmount;
        uint lpTokenPrice;

        //uint allocPoint;
        //uint totalAllocPoint;
        //uint earnedTokenPrice
        //uint secondRewardTokenPrice;
    }
    struct VaultUser {
	    uint allowance;
	    uint tokenBalance;
	    uint stakedBalance;
	    uint stakedWantBalance;
	    uint stakedBalanceUSD;
    }


    mapping(address => VaultFacts[]) public vaultFacts; //vaultHealer =>

    event VaultAdded(VaultFacts facts);
    function sync(address vaultHealerAddress) external {
        //add immutable data for all vaults not already included
        VaultHealer vaultHealer = VaultHealer(vaultHealerAddress);
        uint vhLen = vaultHealer.poolLength();
        uint factLen = vaultFacts[vaultHealerAddress].length;
        //assert(factLen <= vhLen);
        if (vhLen == factLen) revert("already synced");

        require(gasleft() >= GAS_FACTOR * (vhLen - factLen < 50 ? vhLen - factLen : 50)); //ensure enough gas for sync
        VaultFacts[] storage facts = vaultFacts[vaultHealerAddress];

        for (uint i = factLen; i < vhLen; i++) {
            facts.push();
            VaultFacts storage f = facts[i];
            (IERC20 _want, address _strat) = vaultHealer.poolInfo(i);
            uint16 vaultPid = uint16(i);
            uint16 chefPid;
            uint8 tolerance;
            address masterchefAddress;

            try IStrategy(_strat).pid() returns (uint256 _chefPid) {
                chefPid = uint16(_chefPid);
            } catch {}
            try IStrategy(_strat).tolerance() returns (uint256 _tolerance) {
                tolerance = uint8(_tolerance);
            } catch {}
            try IStrategy(_strat).masterchefAddress() returns (address _masterchef) {
                masterchefAddress = _masterchef;
            } catch {}

            //optimized to fit 4 variables in one storage slot
            f.vaultPid = vaultPid;
            f.chefPid = chefPid;
            f.tolerance = tolerance;
            f.masterchefAddress = masterchefAddress;

            f.wantAddress = address(_want);
            f.strategyAddress = _strat;

            IUniPair want = IUniPair(address(_want));

            try want.token0() returns (address _token0) {
                f.token0Address = _token0;
                try want.token1() returns (address _token1) {
                    f.token1Address = _token1;
                    try want.factory() returns (address _factory) {
                        f.lpFactoryAddress = _factory;
                    } catch {}
                } catch {}
            } catch {}

            emit VaultAdded(f);
            if (gasleft() < GAS_FACTOR) return;
        }
    }

    function getVault(address vaultHealerAddress, address priceGetterAddress, address _user, uint pid) public view returns (VaultFacts memory facts, VaultInfo memory info, VaultUser memory user) {
        VaultHealer vaultHealer = VaultHealer(vaultHealerAddress);
        IPriceGetter priceGetter = IPriceGetter(priceGetterAddress);

        facts = vaultFacts[vaultHealerAddress][pid];

        IStrategy strat = IStrategy(facts.strategyAddress);
        try strat.paused() returns (bool _paused) {
            info.paused = _paused;
        } catch {}
        try strat.wantLockedTotal() returns (uint _wantLockedTotal) {
            info.wantLockedTotal = _wantLockedTotal;
        } catch{ }
        try strat.burnedAmount() returns (uint _burnedAmount) {
            info.burnedAmount = _burnedAmount;
        } catch{ }
        try priceGetter.getLPPrice(facts.wantAddress, 18) returns (uint256 price) {
            info.lpTokenPrice = price;
        } catch {}

        /*
        if (facts.masterchefAddress != address(0)) {

            try IMasterchef(facts.masterchefAddress).totalAllocPoint() returns (uint points) {
                info.totalAllocPoint = points;

                address chef = facts.masterchefAddress;
                bytes memory input = abi.encodeWithSignature("poolInfo(uint256)",facts.chefPid);
                bytes memory returndata = Address.functionStaticCall(chef, input);

                if (returndata.length == 0x60) { //MiniChefV2
                    (,,info.allocPoint) = abi.decode(returndata,(uint128,uint64,uint64));
                } else if (returndata.length > 0x60) {
                    (,info.allocPoint,) = abi.decode(returndata,(address,uint256,bytes));
                }
            }   catch {}

        }
        */
        if (_user != address(0)) {
            IERC20 wantToken = IERC20(facts.wantAddress);
            try wantToken.allowance(_user, vaultHealerAddress) returns (uint allowance) {
                user.allowance = allowance;
            } catch {}
            try wantToken.balanceOf(_user) returns (uint _balance) {
                user.tokenBalance = _balance;
            } catch {}
            
            try vaultHealer.userInfo(pid, _user) returns (uint shares) {
                user.stakedBalance = shares;
                uint numerator = shares * info.wantLockedTotal;
                if (numerator > 0) try IStrategy(facts.strategyAddress).sharesTotal() returns (uint sharesTotal) {
                    if (sharesTotal > 0) {
                        user.stakedWantBalance = numerator / sharesTotal;
                        user.stakedBalanceUSD = user.stakedWantBalance * info.lpTokenPrice;
                    }
                } catch {}
            } catch{}
        }
    }

    function getVaults(address vaultHealerAddress, address priceGetterAddress, address user) external view returns (
        VaultFacts[] memory facts, 
        VaultInfo[] memory infos, 
        VaultUser[] memory users
    ) {
        return getVaults(vaultHealerAddress, priceGetterAddress, user, 0, 0);
    }

    function getVaults(address vaultHealerAddress, address priceGetterAddress, address user, uint start, uint end) public view returns (
    VaultFacts[] memory facts, 
    VaultInfo[] memory infos, 
    VaultUser[] memory users
    ) {
        uint len = vaultFacts[vaultHealerAddress].length;
        if (end == 0) end = len;
        if (start >= end || end > len) revert("invalid range");

        facts = new VaultFacts[](end - start);
        infos = new VaultInfo[](end - start);
        users = new VaultUser[](end - start);
        
        for (uint i = start; i < end; i++) {
            (facts[i], infos[i], users[i]) = getVault(vaultHealerAddress, priceGetterAddress, user, i);
        }

    }

    fallback() external {}
}