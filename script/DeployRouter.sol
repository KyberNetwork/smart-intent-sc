// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.s.sol';
import 'src/KSSessionIntentRouter.sol';

contract DeployRouter is BaseScript {
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

    address[] memory guardians = _readAddressArray(
      string(abi.encodePacked(root, '/script/configs/router-guardians.json')), chainId
    );

    vm.startBroadcast();

    KSSessionIntentRouter router = new KSSessionIntentRouter(owner, guardians);

    string memory path = string(abi.encodePacked(root, '/script/deployedAddresses/'));
    _writeAddress(path, chainId, 'router', address(router));

    vm.stopBroadcast();
  }
}
