// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './interfaces/IKSSmartIntentRouter.sol';

abstract contract KSSmartIntentStorage is IKSSmartIntentRouter {
  bytes32 internal constant ACTION_CONTRACT_ROLE = keccak256('ACTION_CONTRACT_ROLE');

  mapping(bytes32 => IntentStatus) internal intentStatuses;

  IKSGenericForwarder internal forwarder;

  address internal feeRecipient;
}
