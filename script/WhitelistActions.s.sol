// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc/script/Base.s.sol';

import 'src/KSSmartIntentRouter.sol';

contract WhitelistActions is BaseScript {
  address[] unWhitelistedContracts;

  function run() external {
    IKSSmartIntentRouter router = IKSSmartIntentRouter(payable(_readAddress('router')));

    address[] memory actionContracts = _readAddressArray('whitelisted-contracts');

    for (uint256 i; i < actionContracts.length; ++i) {
      if (!router.whitelistedActionContracts(actionContracts[i])) {
        unWhitelistedContracts.push(actionContracts[i]);
      }
    }

    vm.startBroadcast();
    router.whitelistActionContracts(unWhitelistedContracts, true);
    vm.stopBroadcast();
  }
}
