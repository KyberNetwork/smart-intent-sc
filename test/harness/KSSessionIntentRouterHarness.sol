// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'src/KSSessionIntentRouter.sol';

contract KSSessionIntentRouterHarness is KSSessionIntentRouter {
  constructor(
    address _owner,
    address[] memory _initialOperators,
    address[] memory _initialGuardians
  ) KSSessionIntentRouter(_owner, _initialOperators, _initialGuardians) {}

  function hashTypedIntentData(IntentData calldata intentData) public view returns (bytes32) {
    return _hashTypedIntentData(intentData);
  }

  function hashTypedActionData(ActionData calldata actionData) public view returns (bytes32) {
    return _hashTypedActionData(actionData);
  }
}
