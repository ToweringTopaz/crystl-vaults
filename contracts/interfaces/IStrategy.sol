// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IUniRouter.sol";
import "../libraries/Fee.sol";
import "../libraries/Tactics.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "./IMagnetite.sol";

interface IStrategy is IERC165 {
    function initialize (bytes calldata data) external;
    function wantToken() external view returns (IERC20); // Want address
    function wantLockedTotal() external view returns (uint256); // Total want tokens managed by strategy
    function earn(Fee.Data[3] memory fees) external returns (bool success, uint256 _wantLockedTotal); // Main want token compounding function
    function deposit(uint256 _wantAmt) external returns (uint256 wantAdded);

    function withdraw(uint256 _wantAmt, uint256 _userLimit) external returns (uint256 sharesRemoved, uint256 wantAmt);
    function panic() external;
    function unpanic() external;
        // Univ2 router used by this strategy
    function router() external view returns (IUniRouter);

    function isMaximizer() external view returns (bool);
    function getMaximizerImplementation() external view returns (address);
    function configInfo() external view returns (
        uint256 vid,
        IERC20 want,
        uint256 wantDust,
        IERC20 rewardToken,
        address masterchef,
        uint pid, 
        IUniRouter _router, 
        IMagnetite _magnetite,
        IERC20[] memory earned,
        uint256[] memory earnedDust,
        uint slippageFactor,
        bool feeOnTransfer
    );
    function tactics() external view returns (Tactics.TacticsA tacticsA, Tactics.TacticsB tacticsB);
    
}