// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'src/KSSmartIntentRouter.sol';

contract KSSmartIntentRouterHarness is KSSmartIntentRouter {
  constructor(
    address initialAdmin,
    address[] memory initialGuardians,
    address[] memory initialRescuers,
    address[] memory initialActionContracts,
    address _forwarder
  )
    KSSmartIntentRouter(
      initialAdmin, initialGuardians, initialRescuers, initialActionContracts, _forwarder
    )
  {}

  function hashTypedIntentData(IntentData calldata intentData) public view returns (bytes32) {
    return _hashTypedDataV4(intentData.hash());
  }

  function hashTypedActionData(ActionData calldata actionData) public view returns (bytes32) {
    return _hashTypedDataV4(actionData.hash());
  }

  function getHasher() public view returns (KSSmartIntentHasher) {
    return hasher;
  }
}
