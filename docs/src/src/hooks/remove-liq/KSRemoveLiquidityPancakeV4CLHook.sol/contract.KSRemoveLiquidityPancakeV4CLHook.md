# KSRemoveLiquidityPancakeV4CLHook
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/hooks/remove-liq/KSRemoveLiquidityPancakeV4CLHook.sol)

**Inherits:**
[BaseTickBasedRemoveLiquidityHook](/src/hooks/base/BaseTickBasedRemoveLiquidityHook.sol/abstract.BaseTickBasedRemoveLiquidityHook.md)


## Functions
### constructor


```solidity
constructor(address _weth) BaseTickBasedRemoveLiquidityHook(_weth);
```

### _validateBeforeExecution


```solidity
function _validateBeforeExecution(IntentData calldata intentData, ActionData calldata actionData)
  internal
  view
  override
  returns (bytes memory beforeExecutionData);
```

### _cacheValidationData


```solidity
function _cacheValidationData(
  PancakeV4CLParams memory pancakeCL,
  RemoveLiquidityHookData calldata validationData,
  bytes calldata hookActionData
) internal view;
```

### _computePositionValues


```solidity
function _computePositionValues(PancakeV4CLParams memory pancakeCL) internal view;
```

### _getFeeGrowthInside


```solidity
function _getFeeGrowthInside(
  ICLPoolManager clPoolManager,
  PoolId poolId,
  int24 tickLower,
  int24 tickCurrent,
  int24 tickUpper
) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128);
```

### _toId


```solidity
function _toId(PoolKey memory poolKey) internal pure returns (PoolId poolId);
```

## Structs
### PancakeV4CLParams
Parameters used for remove liquidity validation of a pancake v4 CL position


```solidity
struct PancakeV4CLParams {
  ICLPoolManager clPoolManager;
  PoolId poolId;
  RemoveLiquidityParams removeLiqParams;
  OutputValidationParams outputParams;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`clPoolManager`|`ICLPoolManager`|The cl pool manager contract|
|`poolId`|`PoolId`|The pool ID|
|`removeLiqParams`|`RemoveLiquidityParams`|The params used to remove liquidity|
|`outputParams`|`OutputValidationParams`|The params used to validate output after execution|

