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

    address owner =
      _readAddress(string(abi.encodePacked(root, '/script/configs/router-owner.json')), chainId);

    address[] memory operators = _readAddressArray(
      string(abi.encodePacked(root, '/script/configs/router-operators.json')), chainId
    );

    address[] memory guardians = _readAddressArray(
      string(abi.encodePacked(root, '/script/configs/router-guardians.json')), chainId
    );

    vm.startBroadcast();

    KSSessionIntentRouter router = new KSSessionIntentRouter(owner, operators, guardians);
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
