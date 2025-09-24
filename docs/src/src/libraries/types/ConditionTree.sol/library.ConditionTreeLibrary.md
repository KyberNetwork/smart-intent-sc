# ConditionTreeLibrary
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/libraries/types/ConditionTree.sol)

Library for condition tree evaluation


## State Variables
### AND

```solidity
OperationType public constant AND = OperationType.AND;
```


### OR

```solidity
OperationType public constant OR = OperationType.OR;
```


## Functions
### evaluateConditionTree

Recursively evaluates a node in a condition tree

*The algorithm assumes that the condition tree structure is valid, meaning:
- No cycle paths exist in the tree
- Each node is only visited once during traversal
- All childrenIndexes point to valid nodes within the array bounds
Invalid tree structures could lead to revert, or invalid results.*


```solidity
function evaluateConditionTree(
  ConditionTree calldata tree,
  uint256 curIndex,
  function(Condition calldata, bytes calldata) view returns (bool) evaluateCondition
) internal view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tree`|`ConditionTree`|the condition tree to be evaluated|
|`curIndex`|`uint256`|index of current node to evaluate (must be < nodes.length and != childIndex)|
|`evaluateCondition`|`function (Condition calldata, bytes calldata) view returns (bool)`|the custom function holding the logic for evaluating the condition of the leaf node|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|true if the condition tree is satisfied, false otherwise|


### isLeaf

Checks if a node is a leaf node


```solidity
function isLeaf(Node calldata node) internal pure returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`node`|`Node`|the node to check|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|true if the node is a leaf node, false otherwise|


### isType

Checks if a condition is of a specific type


```solidity
function isType(Condition calldata condition, ConditionType conditionType)
  internal
  pure
  returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`condition`|`Condition`|the condition to check|
|`conditionType`|`ConditionType`|the type to check against|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|true if the condition is of the specified type, false otherwise|


## Errors
### InvalidNodeIndex

```solidity
error InvalidNodeIndex();
```

### WrongOperationType

```solidity
error WrongOperationType();
```

