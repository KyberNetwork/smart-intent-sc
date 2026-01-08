// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ActionData} from './types/ActionData.sol';
import {ActionWitnessLibrary} from './types/ActionWitness.sol';
import {IntentCoreData} from './types/IntentCoreData.sol';
import {IntentData} from './types/IntentData.sol';

contract KSSmartIntentHasher {
  function hashIntentData(IntentData calldata intentData) public pure returns (bytes32) {
    return intentData.hash();
  }

  function hashActionData(ActionData calldata actionData) public pure returns (bytes32) {
    return actionData.hash();
  }

  function hashActionWitness(IntentCoreData calldata coreData, ActionData calldata actionData)
    public
    pure
    returns (bytes32)
  {
    bytes32 coreDataHash = coreData.hash();
    bytes32 actionDataHash = actionData.hash();
    return keccak256(
      abi.encode(ActionWitnessLibrary.ACTION_WITNESS_TYPE_HASH, coreDataHash, actionDataHash)
    );
  }
}
