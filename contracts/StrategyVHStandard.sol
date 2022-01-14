// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./BaseStrategyVaultHealer.sol";
import "./libs/ITactic.sol";
import "./libs/IVaultHealer.sol";
import {ERC1155Holder} from "./libs/OpenZeppelin.sol";

//This is a strategy contract which can be expected to support 99% of pools. Tactic contracts provide the pool interface.
contract StrategyVHStandard is BaseStrategyVaultHealer, ERC1155Holder {
    using SafeERC20 for IERC20;

    function initEncode(
        IERC20 _wantToken,
        address _masterchefAddress,
        address _tacticAddress,
        uint256 _pid,
        Vault.Settings calldata _settings,
        IERC20[] calldata _earned,
        uint256 _targetVid //maximizer target
    ) external pure returns (bytes memory data) {
        return abi.encode(_wantToken, _masterchefAddress, _tacticAddress, _pid, _settings, _earned, _targetVid);
    }

    function initialize (bytes calldata data) external initializer {
        (IERC20 _wantToken,
        address _masterchefAddress,
        address _tacticAddress,
        uint256 _pid,
        Vault.Settings memory _settings,
        IERC20[] memory _earned,
        uint256 _targetVid //maximizer target
        ) = abi.decode(data,(IERC20,address,address,uint256,Vault.Settings,IERC20[],uint256));

        wantToken = _wantToken;
        _wantToken.safeIncreaseAllowance(msg.sender, type(uint256).max);
        masterchef = _masterchefAddress;
        pid = _pid;
        tactic = ITactic(_tacticAddress);

        //maximizer config
        if (_targetVid != 0) {
            targetVault = IVaultHealer(msg.sender).strat(_targetVid);
            maximizerRewardToken = targetVault.wantToken();
            targetVid = uint32(_targetVid);
            maximizerRewardToken.safeIncreaseAllowance(msg.sender, type(uint256).max);
        }

        for (uint i; i < _earned.length && address(_earned[i]) != address(0); i++) {
            earned[i] = _earned[i];
        }
        
        //Look for LP tokens. If not, want must be a single-stake
        IERC20 swapToToken = _targetVid == 0 ? _wantToken : maximizerRewardToken; //swap earned to want, or swap earned to maximizer target's want
        try IUniPair(address(swapToToken)).token0() returns (IERC20 _token0) {
            lpToken[0] = _token0;
            lpToken[1] = IUniPair(address(swapToToken)).token1();
        } catch { //if not LP, then single stake
            lpToken[0] = swapToToken;
        }

        Vault.check(_settings);
        settings = _settings;
        emit SetSettings(_settings);

        settings.magnetite = IVaultHealer(msg.sender).magnetite();

        // maximizerVault.setFees(
        //                 [
        //         [ ZERO_ADDRESS, FEE_ADDRESS, 0 ], // withdraw fee: token is not set here; standard fee address; 10 now means 0.1% consistent with other fees
        //         [ WMATIC, FEE_ADDRESS, 0 ], //earn fee: wmatic is paid; goes back to caller of earn; 0% rate
        //         [ WMATIC, FEE_ADDRESS, 0 ], //reward fee: paid in DAI; standard fee address; 0% rate
        //         [ CRYSTL, BURN_ADDRESS, 0 ] //burn fee: crystl to burn address; 5% rate
        //     ]
        // );
        
    }
    function vaultSharesTotal() public override view returns (uint256) {
        return tactic.vaultSharesTotal(masterchef, pid);
    }
    
    function _vaultDeposit(uint256 _amount) internal override {
        
        //token allowance for the pool to pull the correct amount of funds only
        wantToken.safeIncreaseAllowance(masterchef, _amount);
        
        delegateToTactic(abi.encodeWithSelector(
            tactic._vaultDeposit.selector, masterchef, pid, _amount));
    }
    
    function _vaultWithdraw(uint256 _amount) internal override {
        delegateToTactic(abi.encodeWithSelector(
            tactic._vaultWithdraw.selector, masterchef, pid, _amount));
    }
    
    function _vaultHarvest() internal override {
        delegateToTactic(abi.encodeWithSelector(
            tactic._vaultHarvest.selector, masterchef, pid));
    }
    
    function _emergencyVaultWithdraw() internal override {
        delegateToTactic(abi.encodeWithSelector(
            tactic._emergencyVaultWithdraw.selector, masterchef, pid
        ));
    }

    function getMaximizerRewardToken() external view returns(IERC20){
        return maximizerRewardToken;
    }

    function withdrawMaximizerReward(uint256 _pid, uint256 _amount) external {
        IVaultHealer(msg.sender).withdraw(_pid, _amount);
    }
    function delegateToTactic(bytes memory _calldata) private {
        (bool success, ) = address(tactic).delegatecall(_calldata);
        require(success, "Tactic function failed");
    }

}