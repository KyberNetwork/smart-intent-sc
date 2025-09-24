# KSRemoveLiquidityUniswapV3Hook
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/hooks/remove-liq/KSRemoveLiquidityUniswapV3Hook.sol)

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

### _getPositionLiquidity


```solidity
function _getPositionLiquidity(address nftAddress, uint256 nftId)
  internal
  view
  override
  returns (uint256 liquidity);
```

### _cacheValidationData


```solidity
function _cacheValidationData(
  UniswapV3Params memory uniswapV3,
  RemoveLiquidityHookData calldata validationData,
  bytes calldata hookActionData
) internal view;
```

### _computePositionValues


```solidity
function _computePositionValues(UniswapV3Params memory uniswapV3) internal view;
```

### _getFeeGrowthInside


```solidity
function _getFeeGrowthInside(
  IUniswapV3Pool pool,
  int24 tickLower,
  int24 tickCurrent,
  int24 tickUpper
) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128);
```

## Structs
### UniswapV3Params
Parameters used for remove liquidity validation of a uniswap v3 position


```solidity
struct UniswapV3Params {
  address pool;
  RemoveLiquidityParams removeLiqParams;
  OutputValidationParams outputParams;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`pool`|`address`|The pool address|
|`removeLiqParams`|`RemoveLiquidityParams`|The params used to remove liquidity|
|`outputParams`|`OutputValidationParams`|The params used to validate output after execution|

