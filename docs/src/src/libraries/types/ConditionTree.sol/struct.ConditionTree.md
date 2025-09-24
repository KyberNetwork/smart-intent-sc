# ConditionTree
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/libraries/types/ConditionTree.sol)


```solidity
struct ConditionTree {
  Node[] nodes;
  bytes[] additionalData;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`nodes`|`Node[]`|the nodes of the condition tree|
|`additionalData`|`bytes[]`|the additional data to be validated or used for validation for each node (should be empty for non-leaf nodes)|

