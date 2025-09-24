# HookLibrary
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/libraries/HookLibrary.sol)


## Functions
### beforeExecution


```solidity
function beforeExecution(
  bytes32 intentHash,
  IntentData calldata intentData,
  address feeRecipient,
  ActionData calldata actionData
) internal returns (uint256[] memory fees, bytes memory beforeExecutionData);
```

### afterExecution


```solidity
function afterExecution(
  bytes32 intentHash,
  IntentData calldata intentData,
  address feeRecipient,
  bytes memory beforeExecutionData,
  bytes memory actionResult
) internal;
```

## Events
### RecordFeeAndVolume

```solidity
event RecordFeeAndVolume(
  address indexed token, address indexed feeRecipient, uint256 fee, uint256 volume
);
```

