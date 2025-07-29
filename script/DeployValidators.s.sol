// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.s.sol';

import 'src/validators/swap-validators/KSPriceBasedDCAIntentValidator.sol';
import 'src/validators/swap-validators/KSTimeBasedDCAIntentValidator.sol';

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

    KSPriceBasedDCAIntentValidator priceBasedDCAValidator =
      new KSPriceBasedDCAIntentValidator(_toArray(router));
    KSTimeBasedDCAIntentValidator timeBasedDCAValidator =
      new KSTimeBasedDCAIntentValidator(_toArray(router));

    string memory path = string(abi.encodePacked(root, '/script/deployedAddresses/'));
    string[] memory keys = new string[](2);
    keys[0] = 'KSPriceBasedDCAIntentValidator';
    keys[1] = 'KSTimeBasedDCAIntentValidator';

    address[] memory addresses = new address[](2);
    addresses[0] = address(priceBasedDCAValidator);
    addresses[1] = address(timeBasedDCAValidator);

    _writeAddress(path, 'validators', chainId, keys, addresses);

    vm.stopBroadcast();
  }
}
