// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "./libs/IVaultHealer.sol";
import "./libs/IBoostPool.sol";
import "./libs/IStrategy.sol";
import "./libs/VaultSettings.sol";
import "hardhat/console.sol";
import "./libs/M1155.sol";

abstract contract VaultHealerBase is AccessControlEnumerable, ReentrancyGuard, IVaultHealer {
    using SafeERC20 for IERC20;

    bytes32 constant STRATEGY = keccak256("STRATEGY");
    bytes32 constant VAULT_ADDER = keccak256("VAULT_ADDER");
    bytes32 constant TESTER = keccak256("TESTER");
    bytes32 constant SETTINGS_SETTER = keccak256("SETTINGS_SETTER");
    uint constant TESTING_DURATION = 12 hours;
    uint constant MAX_VAULTS = 1000000;

    struct VaultInfo {
        IStrategy strat; // Strategy contract that will auto compound want tokens
        
        VaultFee withdrawFee;
        VaultFee[] earnFees;

        VaultSettings settings;
        VaultConfig config;

        IBoostPool[] boosts; //all boosted pools
        BitMaps.BitMap activeBoosts; //boosted pools still active
        mapping(address => BitMaps.BitMap) userBoosts;

        mapping(uint256 => M1155.EarnRatio) ratioByBlock;
        uint32 lastEarnBlock;

        uint112 grandTotalSupply; //sum of totalSupply of all token IDs for this vault
        uint112 pendingImportTotal;
        uint40 panicLockExpiry; //panic can only happen again after the time has elapsed
        uint16 minBlocksBetweenEarns; //Prevents token waste, exploits and unnecessary reverts

        uint40 creationTime;

        EnumerableSet maximizersIn;
        EnumerableSet.UintSet targetsOut;
    }

    struct VaultFee {
        address receiver;
        uint16 rate;
    }

    VaultInfo[] internal _vaultInfo; // Info of each vault.

    //vid for any of our strategies
    mapping(address => uint) private _strats;
    
    event AddVault(address indexed strat);
    event SetSettings(uint indexed vid, VaultSettings _settings);
    
    constructor(address _owner) {
        _setupRole(DEFAULT_ADMIN_ROLE, _owner);
        _setupRole(VAULT_ADDER, _owner);
        _setupRole(SETTINGS_SETTER, _owner);
        _setupRole(TESTER, _owner);
        _setRoleAdmin(STRATEGY, VAULT_ADDER);

        
        _vaultInfo.push(); //so uninitialized vid variables (vid 0) can be assumed as invalid
    }

    /**
     * @dev Add a new want to the vault. Can only be called by the owner.
     */

    function addVault(address _strat, VaultSettings calldata _settings) public virtual nonReentrant returns (uint vid) {
        require(!hasRole(STRATEGY, _strat), "Existing strategy");
        grantRole(STRATEGY, _strat); //requires msg.sender is VAULT_ADDER

        IStrategy strat = IStrategy(_strat);
        vid = _vaultInfo.length;
        assert(vid < MAX_VAULTS);

        _vaultInfo.push();
        VaultInfo storage vault = _vaultInfo[vid];
        //todo: config in factory process //vault.want = strat.wantToken();
        vault.strat = strat;

        check(_settings);
        vault.settings = _settings;
        vault.strat.setSettings(_settings);
        vault.creationTime = uint40(block.timestamp);

        _strats[_strat] = vid;
        emit AddVault(_strat);
        emit SetSettings(vid, _settings);
    }
    /*  todo: implement test vaults and deletion
    function deleteVault(uint _vid) external onlyRole(VAULT_ADDER) nonReentrant {
        VaultInfo storage vault = _vaultInfo[_vid];
    }
    */

    function settings(uint _vid) external view returns (VaultSettings memory) {
        return _vaultInfo[_vid].settings;
    }

    function setSettings(uint _vid, VaultSettings calldata _settings) external onlyRole(SETTINGS_SETTER) {
        VaultInfo storage vault = _vaultInfo[_vid];
        check(_settings);
        vault.strat.setSettings(_settings);
        _vaultInfo[_vid].settings = _settings; //Prevents token waste, exploits and unnecessary reverts
        emit SetSettings(_vid, _settings);
    }

    function isStrat(address _strat) public view returns (bool) {
        return _strats[_strat] > 0;
    }
    function findVid(address _strat) public view returns (uint) {
        uint vid = _strats[_strat];
        require(vid > 0, "address is not a strategy on this VaultHealer"); //must revert here for security
        return vid;
    }


}
