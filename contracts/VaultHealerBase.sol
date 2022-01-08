// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "hardhat/console.sol";
import "./libs/Vault.sol";
import "./libs/LibVaultConfig.sol";
import "./libs/IStrategy.sol";

abstract contract VaultHealerBase is AccessControlEnumerable, ERC1155Supply, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using LibVaultConfig for VaultFees;

    bytes32 public constant STRATEGY = keccak256("STRATEGY");
    bytes32 public constant VAULT_ADDER = keccak256("VAULT_ADDER");
    bytes32 public constant SETTINGS_SETTER = keccak256("SETTINGS_SETTER");

    VaultInfo[] internal _vaultInfo; // Info of each vault.

    //vid for any of our strategies
    mapping(address => uint) private _strats;
    
    event AddVault(address indexed strat);
    
    constructor(address _owner) ERC1155("") {
        _setupRole(DEFAULT_ADMIN_ROLE, _owner);
        _setupRole(VAULT_ADDER, _owner);
        _setRoleAdmin(STRATEGY, VAULT_ADDER);

        _vaultInfo.push(); //so uninitialized vid variables (vid 0) can be assumed as invalid
    }

    /**
     * @dev Add a new want to the vault. Can only be called by the owner.
     */

    function addVault(address _strat, uint minBlocksBetweenEarns) internal virtual nonReentrant returns (uint vid) {
        require(!hasRole(STRATEGY, _strat), "Existing strategy");
        grantRole(STRATEGY, _strat); //requires msg.sender is VAULT_ADDER

        IStrategy strat_ = IStrategy(_strat);
        vid = _vaultInfo.length;
        _vaultInfo.push();
        VaultInfo storage vault = _vaultInfo[vid];
        vault.want = strat_.wantToken();
        //vault.router = strat.router();
        vault.lastEarnBlock = block.number;
        vault.minBlocksBetweenEarns = minBlocksBetweenEarns;
        vault.targetVid = _strats[address(strat_.targetVault())];
        
        _strats[_strat] = vid;
        emit AddVault(_strat);
    }


    function isStrat(address _strat) public view returns (bool) {
        return _strats[_strat] > 0;
    }
    function findVid(address _strat) public view returns (uint) {
        uint vid = _strats[_strat];
        require(vid > 0, "address is not a strategy on this VaultHealer"); //must revert here for security
        return vid;
    }
    function setSettings(uint vid, VaultSettings calldata _settings) external onlyRole(SETTINGS_SETTER) {
        strat(vid).setSettings(_settings);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlEnumerable, ERC1155) returns (bool) {
        return AccessControlEnumerable.supportsInterface(interfaceId) || ERC1155.supportsInterface(interfaceId);
    }

    function strat(uint _vid) public virtual view returns (IStrategy);
}
