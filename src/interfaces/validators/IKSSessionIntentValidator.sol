// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'src/interfaces/routers/IKSSessionIntentRouter.sol';

interface IKSSessionIntentValidator {
  /**
   * @notice Validates the intent before execution
   * @param coreData the core data of the intent
   * @param actionData the data of the action
   * @return beforeExecutionData the data to be used for validation after execution
   */
  function validateBeforeExecution(
    bytes32 intentHash,
    IKSSessionIntentRouter.IntentCoreData calldata coreData,
    IKSSessionIntentRouter.ActionData calldata actionData
  ) external returns (bytes memory beforeExecutionData);

  /**
   * @notice Validates the intent after execution
   * @param coreData the core data of the intent
   * @param beforeExecutionData the data returned from `validateBeforeExecution`
   * @param actionResult the result of the action
   */
  function validateAfterExecution(
    bytes32 intentHash,
    IKSSessionIntentRouter.IntentCoreData calldata coreData,
    bytes calldata beforeExecutionData,
    bytes calldata actionResult
  ) external;
}
