// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./libs/OpenZeppelin.sol";
import "./libs/Vault.sol";
import "./libs/IStrategy.sol";
import "./libs/IVaultHealer.sol";
import "./inter/IVaultFeeManager.sol";
import "./QuartzUniV2Zap.sol";

contract VaultView is AccessControlEnumerable, ERC1155SupplyUpgradeable, IVaultView {

    bytes32 public constant STRATEGY = keccak256("STRATEGY");
    bytes32 public constant VAULT_ADDER = keccak256("VAULT_ADDER");
    bytes32 public constant SETTINGS_SETTER = keccak256("SETTINGS_SETTER");
    bytes32 public constant PATH_SETTER = keccak256("PATH_SETTER");
    bytes32 public constant PAUSER = keccak256("PAUSER");
    bytes32 public constant FEE_SETTER = keccak256("FEE_SETTER");

    IVaultFeeManager public vaultFeeManager;
    Vault.Info[] internal _vaultInfo; // Info of each vault.
    BitMaps.BitMap internal pauseMap; //Boolean pause status for each vault; true == unpaused
    mapping(address => uint32) private _strats;
    uint256 private _lock = type(uint32).max;

/*
    struct PendingDeposit {
        IERC20 token;
        address from;
        uint112 amount;
    }
    PendingDeposit[] private pendingDeposits; //LIFO stack, avoiding complications with maximizers

}
*/
    bytes32 internal __reserved;
    address proxyImplementation;
    bytes proxyMetadata;
    IMagnetite public magnetite;
    QuartzUniV2Zap immutable public zap;
    VaultView public vaultView;

    constructor(QuartzUniV2Zap _zap) {
        zap = _zap;
    }

    function vaultLength() external view returns (uint256) {
        return _vaultInfo.length;
    }
    function paused(uint vid) external view returns (bool) {
        return !BitMaps.get(pauseMap, vid);
    }


}