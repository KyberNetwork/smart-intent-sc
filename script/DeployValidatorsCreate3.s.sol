// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'forge-std/Script.sol';
import {stdJson} from 'forge-std/StdJson.sol';
import {console} from 'forge-std/console.sol';

import './Base.s.sol';
import 'src/validators/KSPriceBasedDCAIntentValidator.sol';
import 'src/validators/KSTimeBasedDCAIntentValidator.sol';

/// @dev This script is used to deploy Validators contract
contract DeployValidatorsCreate3 is BaseScript {
  using stdJson for string;

  string[] internal _contractNames =
    ['KSPriceBasedDCAIntentValidator', 'KSTimeBasedDCAIntentValidator'];

  string internal _releaseVersion = '250714';

  function run() external {
    uint256 chainId;
    assembly ("memory-safe") {
      chainId := chainid()
    }
    console.log('chainId is %s', chainId);

    address router = _readAddress('script/deployedAddresses/router.json', chainId);
    console.log('router is %s', router);

    require(bytes(_releaseVersion).length > 0, 'Release version not set');

    string[] memory keys = new string[](_contractNames.length);
    address[] memory addresses = new address[](_contractNames.length);

    vm.startBroadcast();
    for (uint256 i = 0; i < _contractNames.length; i++) {
      bytes32 salt = keccak256(bytes(string.concat(_contractNames[i], '_', _releaseVersion)));
      bytes memory bytecode =
        abi.encodePacked(vm.getCode(_contractNames[i]), abi.encode(_toArray(router))); // Encodes the contract bytecode for deployment

      address validator = _deployContract(salt, bytecode);

      keys[i] = _contractNames[i];
      addresses[i] = validator;
    }

    vm.stopBroadcast();

    _writeAddress('script/deployedAddresses/', 'validators', chainId, keys, addresses);
  }
}
