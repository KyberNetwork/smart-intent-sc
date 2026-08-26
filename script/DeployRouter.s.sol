// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc/script/Base.s.sol';
import 'src/KSSmartIntentRouter.sol';

struct ActionContract {
  address addr;
  string name;
}

contract DeployRouter is BaseScript {
  string salt = '260209';

  function run() external {
    if (bytes(salt).length == 0) {
      revert('salt is required');
    }
    salt = string.concat('KSSmartIntentRouter_', salt);

    address admin = _readAddress('router-admin');
    address[] memory guardians = _readAddressArray('router-guardians');
    address[] memory rescuers = _readAddressArray('router-rescuers');
    address[] memory actionContracts = _readActionContracts();
    address forwarder = _readAddress('forwarder');

    vm.startBroadcast();

    bytes memory creationCode = abi.encodePacked(
      type(KSSmartIntentRouter).creationCode,
      abi.encode(admin, guardians, rescuers, actionContracts, forwarder)
    );
    address router = _create3Deploy(keccak256(abi.encodePacked(salt)), creationCode);

    _writeAddress('router', router);

    vm.stopBroadcast();
  }

  function _readActionContracts() internal view returns (address[] memory addresses) {
    ActionContract[] memory entries = abi.decode(
      vm.parseJson(_getJsonString('action-contracts'), _toDotChainId(_chainIdUint())),
      (ActionContract[])
    );

    addresses = new address[](entries.length);
    for (uint256 i = 0; i < entries.length; i++) {
      addresses[i] = entries[i].addr;
    }
  }
}
