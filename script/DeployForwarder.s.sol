// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc/script/Base.s.sol';
import 'ks-common-sc/src/KSWhitelistedForwarder.sol';

contract DeployForwarder is BaseScript {
  string salt = '260123';

  function run() external {
    if (bytes(salt).length == 0) {
      revert('salt is required');
    }
    salt = string.concat('KSWhitelistedForwarder_', salt);

    address admin = _readAddress('forwarder-admin');
    address[] memory rescuers = _readAddressArray('forwarder-rescuers');

    vm.startBroadcast();
    bytes memory creationCode =
      abi.encodePacked(type(KSWhitelistedForwarder).creationCode, abi.encode(admin, rescuers));
    (address forwarder,) = _create3Deploy(keccak256(abi.encodePacked(salt)), creationCode);

    _writeAddress('forwarder', forwarder);

    vm.stopBroadcast();
  }
}
