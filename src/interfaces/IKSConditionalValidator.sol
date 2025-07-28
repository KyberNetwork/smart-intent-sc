// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

type ConditionType is bytes32;

enum OperationType {
  AND,
  OR
}

/**
 * @param conditionType the type of the condition
 * @param data the data of the condition
 */
struct Condition {
  ConditionType conditionType;
  bytes data;
}

/**
 * @param operationType the type of the operation (AND or OR)
 * @param condition the condition to be validated
 * @param childrenIndexes the indexes of the children nodes (if the node is a leaf, this is empty)
 */
struct Node {
  OperationType operationType;
  Condition condition;
  uint256[] childrenIndexes;
}

/**
 * @param nodes the nodes of the condition tree
 * @param additionalData the additional data to be validated or used for validation for each node (should be empty for non-leaf nodes)
 */
struct ConditionTree {
  Node[] nodes;
  bytes[] additionalData;
}

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
