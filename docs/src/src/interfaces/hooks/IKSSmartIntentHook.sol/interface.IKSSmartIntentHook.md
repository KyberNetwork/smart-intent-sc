# IKSSmartIntentHook
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/interfaces/hooks/IKSSmartIntentHook.sol)


## Functions
### beforeExecution

Before execution hook


```solidity
function beforeExecution(
  bytes32 intentHash,
  IntentData calldata intentData,
  ActionData calldata actionData
) external returns (uint256[] memory fees, bytes memory beforeExecutionData);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`intentHash`|`bytes32`||
|`intentData`|`IntentData`|the intent data|
|`actionData`|`ActionData`|the data of the action|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`fees`|`uint256[]`|the amount of fees to be taken|
|`beforeExecutionData`|`bytes`|the data representing the state before execution|


### afterExecution

After execution hook


```solidity
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
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`intentHash`|`bytes32`||
|`intentData`|`IntentData`|the intent data|
|`beforeExecutionData`|`bytes`|the data returned from `beforeExecution`|
|`actionResult`|`bytes`|the result of the action|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokens`|`address[]`|the tokens to be taken fees from and to be returned to the recipient|
|`fees`|`uint256[]`|the fees to be taken|
|`amounts`|`uint256[]`|the amounts of the tokens to be returned to the recipient|
|`recipient`|`address`|the address of the recipient|


