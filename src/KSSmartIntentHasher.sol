// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ActionData} from './types/ActionData.sol';
import {ActionWitnessLibrary} from './types/ActionWitness.sol';
import {IntentData} from './types/IntentData.sol';

contract KSSmartIntentHasher {
  function hashIntentData(IntentData calldata intentData) public pure returns (bytes32) {
    return intentData.hash();
  }

  function hashActionWitness(bytes32 intentHash, ActionData calldata actionData)
    public
    pure
    returns (bytes32)
  {
    return keccak256(
      abi.encode(ActionWitnessLibrary.ACTION_WITNESS_TYPE_HASH, intentHash, actionData.hash())
    );
  }
}
