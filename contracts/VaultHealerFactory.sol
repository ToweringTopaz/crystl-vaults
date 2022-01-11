// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./VaultHealerBoostedPools.sol";
import "./VHStrategyProxy.sol";

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
    ) external {
        proxyImplementation = _implementation;
        address newStrat = Create2.deploy(0, bytes32(_vaultInfo.length), type(VHStrategyProxy).creationCode);
        IStrategy(newStrat).initialize(data);
        addVault(newStrat, 10); //qq - what's the 10 here? -- minBlocksBetweenEarns -- todo: does this need to be configurable? In theory it should sort itself
    }
    
    function strat(uint _vid) public override view returns (IStrategy) {
        bytes32 _data = keccak256(abi.encodePacked(bytes1(0xff), address(this), bytes32(_vid), PROXY_CODE_HASH));
        return IStrategy(address(uint160(uint256(_data))));
    }

}