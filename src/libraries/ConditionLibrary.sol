// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'src/interfaces/IKSConditionalValidator.sol';

using ConditionLibrary for ConditionTree;
using ConditionLibrary for Node;

/**
 * @notice Library for condition tree evaluation
 */
library ConditionLibrary {
  error InvalidNodeIndex();
  error WrongOperationType();

  OperationType public constant AND = OperationType.AND;
  OperationType public constant OR = OperationType.OR;

  /**
   * @notice Recursively evaluates a node in a condition tree
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

    bytes calldata additionalData = tree.additionalData[curIndex];

    if (node.isLeaf()) {
      return evaluateCondition(node.condition, additionalData);
    }

    // non-leaf node
    uint256 length = node.childrenIndexes.length;
    uint256 childIndex;
    if (node.operationType == AND) {
      for (uint256 i; i < length; ++i) {
        childIndex = node.childrenIndexes[i];
        require(childIndex != curIndex, InvalidNodeIndex());
        if (!tree.evaluateConditionTree(childIndex, evaluateCondition)) {
          return false;
        }
      }
      return true;
    } else if (node.operationType == OR) {
      for (uint256 i; i < length; ++i) {
        childIndex = node.childrenIndexes[i];
        require(childIndex != curIndex, InvalidNodeIndex());
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
