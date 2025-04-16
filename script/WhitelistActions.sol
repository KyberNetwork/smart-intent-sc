// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.s.sol';
import {IKSSessionIntentRouter} from 'src/interfaces/IKSSessionIntentRouter.sol';

contract WhitelistActions is BaseScript {
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

    (address[] memory swapRouters, bytes4[] memory selectors) = _readSwapRouterAddresses(
      string(abi.encodePacked(root, '/script/configs/whitelisted-actions.json')), chainId
    );

    vm.startBroadcast();
    IKSSessionIntentRouter(router).whitelistActions(swapRouters, selectors, true);
    vm.stopBroadcast();
  }
}
