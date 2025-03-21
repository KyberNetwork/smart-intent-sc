// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'src/interfaces/IKSSessionIntentValidator.sol';

contract MockIntentValidator is IKSSessionIntentValidator {
  function validateBeforeExecution(
    IKSSessionIntentRouter.IntentCoreData calldata coreData,
    bytes calldata actionCallData
  ) external view returns (bytes memory beforeExecutionData) {}

  function validateAfterExecution(
    IKSSessionIntentRouter.IntentCoreData calldata coreData,
    bytes calldata beforeExecutionData,
    bytes calldata actionResult
  ) external view {}
}
