# Node
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/libraries/types/ConditionTree.sol)


```solidity
struct Node {
  OperationType operationType;
  Condition condition;
  uint256[] childrenIndexes;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`operationType`|`OperationType`|the type of the operation (AND or OR)|
|`condition`|`Condition`|the condition to be validated|
|`childrenIndexes`|`uint256[]`|the indexes of the children nodes (if the node is a leaf, this is empty)|

