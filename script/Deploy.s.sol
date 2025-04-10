// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.s.sol';

import 'src/KSSessionIntentRouter.sol';

import 'src/validators/KSPriceBasedDCAIntentValidator.sol';
import 'src/validators/KSSwapIntentValidator.sol';
import 'src/validators/KSTimeBasedDCAIntentValidator.sol';

contract DeployScript is BaseScript {
  function run() external {
    string memory root = vm.projectRoot();
    uint256 chainId;
    assembly ("memory-safe") {
      chainId := chainid()
    }
    console.log('chainId is %s', chainId);

    address weth =
      _readAddress(string(abi.encodePacked(root, '/script/configs/weth.json')), chainId);
    console.log('WETH is %s', weth);

    address[] memory addresses = _readAddressArray(
      string(abi.encodePacked(root, '/script/configs/initAddresses.json')), chainId
    );

    console.log('owner is %s', addresses[0]);
    console.log('operator is %s', addresses[1]);
    console.log('guardian is %s', addresses[2]);

    vm.startBroadcast();

    KSSessionIntentRouter router =
      new KSSessionIntentRouter(addresses[0], _toArray(addresses[1]), _toArray(addresses[2]));
    KSSwapIntentValidator swapValidator = new KSSwapIntentValidator();
    KSPriceBasedDCAIntentValidator priceBasedDCAValidator = new KSPriceBasedDCAIntentValidator();
    KSTimeBasedDCAIntentValidator timeBasedDCAValidator = new KSTimeBasedDCAIntentValidator();

    console.log('router is %s', address(router));
    console.log('swapValidator is %s', address(swapValidator));
    console.log('priceBasedDCAValidator is %s', address(priceBasedDCAValidator));
    console.log('timeBasedDCAValidator is %s', address(timeBasedDCAValidator));

    vm.stopBroadcast();
  }
}
