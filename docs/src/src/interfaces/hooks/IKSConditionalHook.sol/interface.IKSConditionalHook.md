# IKSConditionalHook
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/interfaces/hooks/IKSConditionalHook.sol)


## Functions
### validateConditionTree

Validates a condition tree starting from the specified root node

*Reverts with ConditionsNotMet() if the conditions are not met*


```solidity
function validateConditionTree(ConditionTree calldata conditionTree, uint256 rootIndex)
  external
  view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`conditionTree`|`ConditionTree`|The hierarchical structure of conditions to evaluate|
|`rootIndex`|`uint256`|The index of the root node to start evaluation from|


### evaluateCondition


```solidity
function evaluateCondition(Condition calldata condition, bytes calldata additionalData)
  external
  view
  returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`condition`|`Condition`|the condition to be evaluated|
|`additionalData`|`bytes`|the additional data to be used for evaluation|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|true if the condition is met, false otherwise|


## Errors
### ConditionsNotMet

```solidity
error ConditionsNotMet();
```

