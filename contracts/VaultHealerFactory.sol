// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./VaultHealerBoostedPools.sol";
import "./VHStrategyProxy.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

abstract contract VaultHealerFactory is VaultHealerBoostedPools {

    bytes32 constant PROXY_CODE_HASH = keccak256(type(VHStrategyProxy).creationCode);
    address proxyImplementation;
    bytes proxyMetadata;

    function getProxyData() external returns (address _implementation, bytes memory _metadata) {
        _implementation = proxyImplementation;
        _metadata = proxyMetadata;
        delete proxyImplementation;
        delete proxyMetadata;
    }

    function createVault(
        address _implementation,
        bytes calldata data
    ) external onlyRole("VAULT_ADDER") {
        proxyImplementation = _implementation;
        address newStrat = Create2.deploy(0, bytes32(_vaultInfo.length), type(VHStrategyProxy).creationCode);
        IStrategy(newStrat).initialize(data);
        addVault(newStrat, 10);
    }
    
    function strat(uint _vid) internal override view returns (IStrategy) {
        bytes32 _data = keccak256(abi.encodePacked(bytes1(0xff), address(this), bytes32(_vid), PROXY_CODE_HASH));
        return IStrategy(address(uint160(uint256(_data))));
    }

}