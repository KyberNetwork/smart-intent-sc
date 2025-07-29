// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'src/libraries/ConditionTreeLibrary.sol';

interface IKSConditionalValidator {
  error ConditionsNotMet();

  /**
   * @notice Validates a condition tree starting from the specified root node
   * @dev Reverts with ConditionsNotMet() if the conditions are not met
   * @param conditionTree The hierarchical structure of conditions to evaluate
   * @param rootIndex The index of the root node to start evaluation from
   */
  function validateConditionTree(ConditionTree calldata conditionTree, uint256 rootIndex)
    external
    view;

  /**
   * @param condition the condition to be evaluated
   * @param additionalData the additional data to be used for evaluation
   * @return true if the condition is met, false otherwise
   */
  function evaluateCondition(Condition calldata condition, bytes calldata additionalData)
    external
    view
    returns (bool);
}
