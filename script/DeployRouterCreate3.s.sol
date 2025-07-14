// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'forge-std/Script.sol';
import {stdJson} from 'forge-std/StdJson.sol';
import {console} from 'forge-std/console.sol';

import './Base.s.sol';
import 'src/KSSessionIntentRouter.sol';

/// @dev This script is used to deploy Router contract
contract DeployRouterCreate3 is BaseScript {
  using stdJson for string;

  string internal _contractName = 'KSSessionIntentRouter';
  string internal _releaseVersion;

  function run() external {
    uint256 chainId;
    assembly ("memory-safe") {
      chainId := chainid()
    }
    console.log('chainId is %s', chainId);

    address owner = _readAddress('script/configs/router-owner.json', chainId);
    address[] memory guardians = _readAddressArray('script/configs/router-guardians.json', chainId);

    require(bytes(_releaseVersion).length > 0, 'Release version not set');

    vm.startBroadcast();
    bytes32 salt = keccak256(bytes(string.concat(_contractName, '_', _releaseVersion)));
    bytes memory bytecode =
      abi.encodePacked(vm.getCode(_contractName), abi.encode(owner, guardians)); // Encodes the contract bytecode for deployment

    address router = _deployContract(salt, bytecode);
    vm.stopBroadcast();

    _writeAddress('script/deployedAddresses/', 'router', chainId, address(router));
  }
}
