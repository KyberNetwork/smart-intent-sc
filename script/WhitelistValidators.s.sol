// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.s.sol';

import {KSSessionIntentRouter} from 'src/KSSessionIntentRouter.sol';
import {IKSSessionIntentRouter} from 'src/interfaces/routers/IKSSessionIntentRouter.sol';

contract WhitelistValidators is BaseScript {
  address[] unWhitelistedValidators;

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
    (, address[] memory validators) = _readValidatorAddresses(
      string(abi.encodePacked(root, '/script/deployedAddresses/validators.json')), chainId
    );

    for (uint256 i; i < validators.length; ++i) {
      if (!KSSessionIntentRouter(router).whitelistedValidators(validators[i])) {
        unWhitelistedValidators.push(validators[i]);
      }
    }

    vm.startBroadcast();
    IKSSessionIntentRouter(router).whitelistValidators(unWhitelistedValidators, true);
    vm.stopBroadcast();
  }
}
