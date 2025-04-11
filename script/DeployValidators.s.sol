// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.s.sol';

import 'src/validators/KSPriceBasedDCAIntentValidator.sol';
import 'src/validators/KSSwapIntentValidator.sol';
import 'src/validators/KSTimeBasedDCAIntentValidator.sol';

contract DeployValidators is BaseScript {
  function run() external {
    string memory root = vm.projectRoot();
    uint256 chainId;
    assembly ("memory-safe") {
      chainId := chainid()
    }
    console.log('chainId is %s', chainId);

    address router =
      _readAddress(string(abi.encodePacked(root, '/script/deployedAddresses/router.json')), chainId);
    console.log('router is %s', router);

    vm.startBroadcast();

    KSSwapIntentValidator swapValidator = new KSSwapIntentValidator();
    KSPriceBasedDCAIntentValidator priceBasedDCAValidator =
      new KSPriceBasedDCAIntentValidator(_toArray(router));
    KSTimeBasedDCAIntentValidator timeBasedDCAValidator =
      new KSTimeBasedDCAIntentValidator(_toArray(router));

    string memory path = string(abi.encodePacked(root, '/script/deployedAddresses/'));
    _writeAddress(path, chainId, 'swapValidator', address(swapValidator));
    _writeAddress(path, chainId, 'priceBasedDCAValidator', address(priceBasedDCAValidator));
    _writeAddress(path, chainId, 'timeBasedDCAValidator', address(timeBasedDCAValidator));

    vm.stopBroadcast();
  }
}
