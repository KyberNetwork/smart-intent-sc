// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'src/interfaces/validators/IKSConditionalValidator.sol';

using ConditionTreeLibrary for ConditionTree global;
using ConditionTreeLibrary for Node global;
using ConditionTreeLibrary for Condition global;

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

/**
 * @notice Library for condition tree evaluation
 */
library ConditionTreeLibrary {
  error InvalidNodeIndex();
  error WrongOperationType();

  OperationType public constant AND = OperationType.AND;
  OperationType public constant OR = OperationType.OR;

  /**
   * @notice Recursively evaluates a node in a condition tree
   * @dev The algorithm assumes that the condition tree structure is valid, meaning:
   *      - No cycle paths exist in the tree
   *      - Each node is only visited once during traversal
   *      - All childrenIndexes point to valid nodes within the array bounds
   *      Invalid tree structures could lead to revert, or invalid results.
   * @param tree the condition tree to be evaluated
   * @param curIndex index of current node to evaluate (must be < nodes.length and != childIndex)
   * @param evaluateCondition the custom function holding the logic for evaluating the condition of the leaf node
   * @return true if the condition tree is satisfied, false otherwise
   */
  function evaluateConditionTree(
    ConditionTree calldata tree,
    uint256 curIndex,
    function(Condition calldata, bytes calldata) view returns (bool) evaluateCondition
  ) internal view returns (bool) {
    require(curIndex < tree.nodes.length, InvalidNodeIndex());
    Node calldata node = tree.nodes[curIndex];

    if (node.isLeaf()) {
      return evaluateCondition(node.condition, tree.additionalData[curIndex]);
    }

    // non-leaf node
    uint256 length = node.childrenIndexes.length;
    uint256 childIndex;
    if (node.operationType == AND) {
      for (uint256 i; i < length; ++i) {
        childIndex = node.childrenIndexes[i];
        if (!tree.evaluateConditionTree(childIndex, evaluateCondition)) {
          return false;
        }
      }
      return true;
    } else if (node.operationType == OR) {
      for (uint256 i; i < length; ++i) {
        childIndex = node.childrenIndexes[i];
        if (tree.evaluateConditionTree(childIndex, evaluateCondition)) {
          return true;
        }
      }
      return false;
    } else {
      revert WrongOperationType();
    }
  }

  /**
   * @notice Checks if a node is a leaf node
   * @param node the node to check
   * @return true if the node is a leaf node, false otherwise
   */
  function isLeaf(Node calldata node) internal pure returns (bool) {
    return node.childrenIndexes.length == 0;
  }

  /**
   * @notice Checks if a condition is of a specific type
   * @param condition the condition to check
   * @param conditionType the type to check against
   * @return true if the condition is of the specified type, false otherwise
   */
  function isType(Condition calldata condition, ConditionType conditionType)
    internal
    pure
    returns (bool)
  {
    return ConditionType.unwrap(condition.conditionType) == ConditionType.unwrap(conditionType);
  }
}
