// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ActionData} from './types/ActionData.sol';
import {ActionWitness} from './types/ActionWitness.sol';
import {IntentData} from './types/IntentData.sol';

contract KSSmartIntentHasher {
  function hash(IntentData calldata intentData) public pure returns (bytes32) {
    return intentData.hash();
  }

  function hash(ActionData calldata actionData) public pure returns (bytes32) {
    return actionData.hash();
  }

  function hash(ActionWitness calldata actionWitness) public pure returns (bytes32) {
    return actionWitness.hash();
  }
}
