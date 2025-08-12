// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc/script/Base.s.sol';
import 'src/KSSmartIntentRouter.sol';

contract DeployRouter is BaseScript {
  function run() external {
    address admin = _readAddress('router-admin');
    address[] memory guardians = _readAddressArray('router-guardians');
    address[] memory rescuers = _readAddressArray('router-rescuers');
    address feeRecipient = _readAddress('fee-recipient');
    address forwarder = _readAddress('forwarder');

    vm.startBroadcast();

    KSSmartIntentRouter router = new KSSmartIntentRouter(
      admin, guardians, rescuers, feeRecipient, IKSGenericForwarder(forwarder)
    );

    _writeAddress('router', address(router));

    vm.stopBroadcast();
  }
}
