// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./libs/OpenZeppelin.sol";
import "./libs/Vault.sol";
import "./libs/IStrategy.sol";
import "./libs/IVaultHealer.sol";
import "./libs/IVaultFeeManager.sol";
import "./QuartzUniV2Zap.sol";
import "./VHStrategyProxy.sol";
contract VaultView is AccessControlEnumerable, ERC1155SupplyUpgradeable, IVaultView {

    bytes32 public constant STRATEGY = keccak256("STRATEGY");
    bytes32 public constant VAULT_ADDER = keccak256("VAULT_ADDER");
    bytes32 public constant SETTINGS_SETTER = keccak256("SETTINGS_SETTER");
    bytes32 public constant PATH_SETTER = keccak256("PATH_SETTER");
    bytes32 public constant PAUSER = keccak256("PAUSER");
    bytes32 public constant FEE_SETTER = keccak256("FEE_SETTER");
    //bytes constant PROXY_CODE = hex'600063ad3b358e815260408160048384335af150805180601d578182fd5b755af491505b503d82833e806081573d82fd5b503d81f360665260505260205180604060863e67366000818182377360c01b3360201b1782527f331415603757633074440c813560e01c141560335733ff5b8091505b30331415601c527f6042578091505b8082801560565782833685305afa91506074565b8283368573603c526086810182f3';
    bytes32 constant PROXY_CODE_HASH = keccak256(type(VHStrategyProxy).creationCode);
    //bytes32 constant PROXY_CODE_HASH = keccak256(PROXY_CODE);

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

    function userTotals(uint256 vid, address user) external view 
        returns (Vault.TransferData memory stats, int256 earned) 
    {
        stats = _vaultInfo[vid].user[user].stats;
        
        uint _ts = totalSupply(vid);
        uint staked = _ts == 0 ? 0 : balanceOf(user, vid) * strat(vid).wantLockedTotal() / _ts;
        earned = int(stats.withdrawals + staked + stats.transfersOut) - int(uint(stats.deposits + stats.transfersIn));
    }
}