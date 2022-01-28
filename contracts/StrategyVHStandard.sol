// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./BaseStrategyVaultHealer.sol";
import "./libs/IVaultHealer.sol";
import {ERC1155Holder} from "./libs/OpenZeppelin.sol";

//This is a strategy contract which can be expected to support 99% of pools. Tactic contracts provide the pool interface.
contract StrategyVHStandard is BaseStrategyVaultHealer, ERC1155Holder {
    using SafeERC20 for IERC20;

    function configure(
        Settings memory s
    ) external view returns (bytes memory data) {
        
        IERC20 swapToToken = s.wantToken; //swap earned to want, or swap earned to maximizer target's want
        //maximizer config
        if (s.targetVid != 0) {
            (swapToToken,) = IVaultHealer(msg.sender).vaultInfo(s.targetVid);
        }
                
        //Look for LP tokens. If not, want must be a single-stake
        try IUniPair(address(swapToToken)).token0() returns (IERC20 _token0) {
            s.lpToken[0] = _token0;
            s.lpToken[1] = IUniPair(address(swapToToken)).token1();
        } catch { //if not LP, then single stake
            s.lpToken[0] = swapToToken;
        }

        return abi.encode(s);
    }

    function initialize(bytes calldata) external initializer {
        Settings memory s = getSettings();
        
        s.wantToken.safeApprove(msg.sender, 0);
        s.wantToken.safeIncreaseAllowance(msg.sender, type(uint256).max);

        IERC20 swapToToken = s.wantToken; //swap earned to want, or swap earned to maximizer target's want
        //maximizer config
        if (s.targetVid != 0) {
            (swapToToken,) = IVaultHealer(msg.sender).vaultInfo(s.targetVid);
            swapToToken.safeApprove(msg.sender, 0);
            swapToToken.safeIncreaseAllowance(msg.sender, type(uint256).max);
        }

    }

    function withdrawMaximizerReward(uint256 _pid, uint256 _amount) external {
        IVaultHealer(msg.sender).withdraw(_pid, _amount);
    }

}