// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc-script/script/Base.s.sol';
import 'src/KSSmartIntentRouter.sol';

struct ActionContract {
  address addr;
  string name;
}

contract DeployRouter is BaseScript {
  string salt = '260209';

  /**
   * @notice Deploys KSSmartIntentRouter on every chain in `chainIds`
   * @dev Usage:
   *   forge script script/DeployRouter.s.sol --sig "run(string[])" "[56,8453]" \
   *     --account <deployer> --broadcast
   */
  function run(string[] memory chainIds) external multiChain(chainIds) {
    if (bytes(salt).length == 0) {
      revert('salt is required');
    }
    string memory contractSalt = string.concat('KSSmartIntentRouter_', salt);

    address admin = _readAddress('router-admin');
    address[] memory guardians = _readAddressArray('router-guardians');
    address[] memory rescuers = _readAddressArray('router-rescuers');
    address[] memory actionContracts = _readActionContracts();
    address forwarder = _readAddress('forwarder');

    bytes memory creationCode = abi.encodePacked(
      type(KSSmartIntentRouter).creationCode,
      abi.encode(admin, guardians, rescuers, actionContracts, forwarder)
    );
    (address router,) = _create3Deploy(keccak256(abi.encodePacked(contractSalt)), creationCode);

    _writeAddress('router', router);
  }

  function _readActionContracts() internal view returns (address[] memory addresses) {
    ActionContract[] memory entries = abi.decode(
      vm.parseJson(_getJsonString('action-contracts'), _toDotChainId(vm.getChainId())),
      (ActionContract[])
    );

    addresses = new address[](entries.length);
    for (uint256 i = 0; i < entries.length; i++) {
      addresses[i] = entries[i].addr;
    }
  }
}
