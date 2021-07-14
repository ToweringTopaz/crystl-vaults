// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

/*
Join us at PolyCrystal.Finance!
█▀▀█ █▀▀█ █░░ █░░█ █▀▀ █▀▀█ █░░█ █▀▀ ▀▀█▀▀ █▀▀█ █░░ 
█░░█ █░░█ █░░ █▄▄█ █░░ █▄▄▀ █▄▄█ ▀▀█ ░░█░░ █▄▄█ █░░ 
█▀▀▀ ▀▀▀▀ ▀▀▀ ▄▄▄█ ▀▀▀ ▀░▀▀ ▄▄▄█ ▀▀▀ ░░▀░░ ▀░░▀ ▀▀▀
*/

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


interface IMasterHealer {

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of CRYSTLs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accCrystalPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accCrystalPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each user that stakes LP tokens.
    // mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    function userInfo(uint256, address) external view returns (uint256, uint256);


    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. CRYSTLs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that CRYSTLs distribution occurs.
        uint256 accCrystalPerShare;   // Accumulated CRYSTLs per share, times 1e18. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
    }
    
    function poolInfo(uint _pid) external view returns (address _lpToken, uint256 allocPoint, uint256 lastRewardBlock, uint256 accCrystalPerShare, uint16 depositFeeBP);

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 crystalPerBlock);

    function poolLength() external view returns (uint256);

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IERC20 _lpToken, uint16 _depositFeeBP, bool _withUpdate) external;

    // Update the given pool's CRYSTL allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) external;

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) external view returns (uint256);

    // View function to see pending CRYSTLs on frontend.
    function pendingCrystal(uint256 _pid, address _user) external view returns (uint256);

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() external;

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) external;

    // Deposit LP tokens to MasterHealer for CRYSTL allocation.
    function deposit(uint256 _pid, uint256 _amount) external;

    // Withdraw LP tokens from MasterHealer.
    function withdraw(uint256 _pid, uint256 _amount) external;

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external;

    // Update dev address by the previous dev.
    function dev(address _devaddr) external;

    function setFeeAddress(address _feeAddress) external;

    function updateEmissionRate(uint256 _crystalPerBlock) external;
    
}
