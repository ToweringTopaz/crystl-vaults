// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./VaultHealerBase.sol";
import "./VHStrategyProxy.sol";

abstract contract VaultHealerFactory is VaultHealerBase {

    //bytes constant PROXY_CODE = hex"63ad3b358e34526014605c600434335afa5067366000818182377360c01b3360201b1734526040605b601c39601660456070393d6013198101601460863e6072810134f3fe5af491505b503d82833e806081573d82fd5b503d81f3331415603757633074440c813560e01c141560335733ff5b8091505b303314156042578091505b8082801560565782833685305afa91506074565b8283368573";
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
    ) external nonReentrant {
        proxyImplementation = _implementation;
        address newStrat = Create2.deploy(0, bytes32(_vaultInfo.length), type(VHStrategyProxy).creationCode);
        console.log("newStrat: ", newStrat);
        IStrategy(newStrat).initialize(data);
        addVault(newStrat); //qq - what's the 10 here? -- minBlocksBetweenEarns -- todo: does this need to be configurable? In theory it should sort itself
    }
/*
    function createVault(
        address _implementation,
        bytes calldata _metadata,
        bytes calldata data
    ) external nonReentrant {
        proxyData = abi.encodePacked(_implementation, _metadata);
        address newStrat = Create2.deploy(0, bytes32(_vaultInfo.length), PROXY_CODE);
        IStrategy(newStrat).initialize(data);
        addVault(newStrat); //qq - what's the 10 here? -- minBlocksBetweenEarns -- todo: does this need to be configurable? In theory it should sort itself
    }
*/

    
    function strat(uint _vid) internal override view returns (IStrategy) {
        bytes32 _data = keccak256(abi.encodePacked(bytes1(0xff), address(this), bytes32(_vid), PROXY_CODE_HASH));
        return IStrategy(address(uint160(uint256(_data))));
    }

}