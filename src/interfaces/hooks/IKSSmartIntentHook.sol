// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../IKSSmartIntentRouter.sol';

interface IKSSmartIntentHook {
  /**
   * @notice Before execution hook
   * @param intentData the intent data
   * @param actionData the data of the action
   * @return fees the amount of fees to be taken
   * @return beforeExecutionData the data representing the state before execution
   */
  function beforeExecution(
    bytes32 intentHash,
    IntentData calldata intentData,
    ActionData calldata actionData
  ) external returns (uint256[] memory fees, bytes memory beforeExecutionData);

  /**
   * @notice After execution hook
   * @param intentData the intent data
   * @param beforeExecutionData the data returned from `beforeExecution`
   * @param actionResult the result of the action
   * @return tokens the tokens to be taken fees from and to be returned to the recipient
   * @return fees the fees to be taken
   * @return amounts the amounts of the tokens to be returned to the recipient
   * @return recipient the address of the recipient
   */
  function afterExecution(
    bytes32 intentHash,
    IntentData calldata intentData,
    bytes calldata beforeExecutionData,
    bytes calldata actionResult
  )
    external
    returns (
      address[] memory tokens,
      uint256[] memory fees,
      uint256[] memory amounts,
      address recipient
    );
}
