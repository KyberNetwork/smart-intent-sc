# KSRemoveLiquidityUniswapV4Hook
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/hooks/remove-liq/KSRemoveLiquidityUniswapV4Hook.sol)

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
  UniswapV4Params memory uniswapV4,
  RemoveLiquidityHookData calldata validationData,
  bytes calldata hookActionData
) internal view;
```

### _computePositionValues


```solidity
function _computePositionValues(UniswapV4Params memory uniswapV4) internal view;
```

## Structs
### UniswapV4Params
Parameters used for remove liquidity validation of a uniswap v4 position


```solidity
struct UniswapV4Params {
  IPoolManager poolManager;
  RemoveLiquidityParams removeLiqParams;
  OutputValidationParams outputParams;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`poolManager`|`IPoolManager`|The pool manager contract|
|`removeLiqParams`|`RemoveLiquidityParams`|The params used to remove liquidity|
|`outputParams`|`OutputValidationParams`|The params used to validate output after execution|

