// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./libs/OpenZeppelin.sol";
import "./libs/Vault.sol";
import "./libs/IStrategy.sol";
import "./libs/IVaultHealer.sol";
import "./VHStrategyProxy.sol";

contract VaultView is AccessControlEnumerable, ERC1155SupplyUpgradeable, IVaultView {

    bytes32 public constant STRATEGY = keccak256("STRATEGY");
    bytes32 public constant VAULT_ADDER = keccak256("VAULT_ADDER");
    bytes32 public constant SETTINGS_SETTER = keccak256("SETTINGS_SETTER");
    bytes32 public constant PATH_SETTER = keccak256("PATH_SETTER");
    bytes32 public constant PAUSER = keccak256("PAUSER");
    bytes32 public constant FEE_SETTER = keccak256("FEE_SETTER");
    bytes32 constant PROXY_CODE_HASH = keccak256(type(VHStrategyProxy).creationCode);

    Vault.Info[] internal _vaultInfo; // Info of each vault.
    mapping(address => uint32) private _strats;
    uint256 private _lock = type(uint32).max;
    BitMaps.BitMap internal pauseMap; //Boolean pause status for each vault; true == unpaused

    BitMaps.BitMap internal _overrideDefaultEarnFees; // strategy's fee config doesn't change with the vaulthealer's default
    BitMaps.BitMap private _overrideDefaultWithdrawFee;
    Vault.Fees public defaultEarnFees; // Settings which are generally applied to all strategies
    Vault.Fee public defaultWithdrawFee; //withdrawal fee is set separately from earn fees
/*
    struct PendingDeposit {
        IERC20 token;
        address from;
        uint112 amount;
    }
    PendingDeposit[] private pendingDeposits; //LIFO stack, avoiding complications with maximizers

    address proxyImplementation;
    bytes proxyMetadata;
}
*/
    bytes32[3] internal __reserved;

    function vaultLength() external view returns (uint256) {
        return _vaultInfo.length;
    }

    function owner() external view returns (address) {
        return getRoleMember(DEFAULT_ADMIN_ROLE, 0);
    }
    
    function vaultInfo(uint vid) external view returns (IERC20 want, IStrategy _strat) {
        return (_vaultInfo[vid].want, strat(vid));
    }
    function rewardDebt(uint vid, address _user) external view returns (uint) {
        return _vaultInfo[vid].user[_user].rewardDebt;
    }
    // View function to see staked Want tokens on frontend.
    function stakedWantTokens(uint256 _vid, address _user) external view returns (uint256) {
        uint256 _sharesTotal = totalSupply(_vid);
        if (_sharesTotal == 0) return 0;
        
        uint256 wantLockedTotal = strat(_vid).wantLockedTotal();
        
        return balanceOf(_user, _vid) * wantLockedTotal / _sharesTotal;
    }
    function strat(uint _vid) public view returns (IStrategy) {
        bytes32 _data = keccak256(abi.encodePacked(bytes1(0xff), address(this), bytes32(_vid), PROXY_CODE_HASH));
        return IStrategy(address(uint160(uint256(_data))));
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlEnumerable, ERC1155Upgradeable) returns (bool) {
        return AccessControlEnumerable.supportsInterface(interfaceId) || ERC1155Upgradeable.supportsInterface(interfaceId) || interfaceId == type(IVaultHealer).interfaceId;
    }
}