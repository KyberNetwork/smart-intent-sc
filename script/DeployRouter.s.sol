// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc/script/Base.s.sol';
import 'src/KSSmartIntentRouter.sol';

contract DeployRouter is BaseScript {
  string salt = '';

  function run() external {
    if (bytes(salt).length == 0) {
      revert('salt is required');
    }
    salt = string.concat('KSSmartIntentRouter_', salt);

    address admin = _readAddress('router-admin');
    address[] memory guardians = _readAddressArray('router-guardians');
    address[] memory rescuers = _readAddressArray('router-rescuers');
    address[] memory actionContracts = _readAddressArray('action-contracts');
    address feeRecipient = _readAddress('fee-recipient');
    address forwarder = _readAddress('forwarder');

    vm.startBroadcast();

    bytes memory creationCode = abi.encodePacked(
      type(KSSmartIntentRouter).creationCode,
      abi.encode(admin, guardians, rescuers, actionContracts, feeRecipient, forwarder)
    );
    address router = _create3Deploy(keccak256(abi.encodePacked(salt)), creationCode);

    _writeAddress('router', router);

    vm.stopBroadcast();
  }
}
