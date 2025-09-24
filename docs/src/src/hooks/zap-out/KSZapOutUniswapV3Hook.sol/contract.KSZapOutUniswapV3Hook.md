# KSZapOutUniswapV3Hook
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/hooks/zap-out/KSZapOutUniswapV3Hook.sol)

**Inherits:**
[BaseHook](/src/hooks/base/BaseHook.sol/abstract.BaseHook.md)


## State Variables
### RATE_DENOMINATOR

```solidity
uint256 public constant RATE_DENOMINATOR = 1e18;
```


## Functions
### checkTokenLengths


```solidity
modifier checkTokenLengths(ActionData calldata actionData) override;
```

### beforeExecution

Before execution hook


```solidity
function beforeExecution(bytes32, IntentData calldata intentData, ActionData calldata actionData)
  external
  view
  override
  checkTokenLengths(actionData)
  returns (uint256[] memory fees, bytes memory beforeExecutionData);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`||
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
  bytes32,
  IntentData calldata intentData,
  bytes calldata beforeExecutionData,
  bytes calldata
) external view override returns (address[] memory, uint256[] memory, uint256[] memory, address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`||
|`intentData`|`IntentData`|the intent data|
|`beforeExecutionData`|`bytes`|the data returned from `beforeExecution`|
|`<none>`|`bytes`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address[]`|tokens the tokens to be taken fees from and to be returned to the recipient|
|`<none>`|`uint256[]`|fees the fees to be taken|
|`<none>`|`uint256[]`|amounts the amounts of the tokens to be returned to the recipient|
|`<none>`|`address`|recipient the address of the recipient|


### _getPositionLiquidity


```solidity
function _getPositionLiquidity(address nftAddress, uint256 nftId, uint256 liquidityOffset)
  internal
  view
  returns (uint256 liquidity);
```

### _getSqrtPriceX96


```solidity
function _getSqrtPriceX96(address pool, uint256 priceOffset)
  internal
  view
  returns (uint160 sqrtPriceX96);
```

## Errors
### InvalidZapOutPosition

```solidity
error InvalidZapOutPosition();
```

### OutsidePriceRange

```solidity
error OutsidePriceRange(uint160 sqrtPLower, uint160 sqrtPUpper, uint160 sqrtPriceX96);
```

### InvalidOwner

```solidity
error InvalidOwner();
```

### GetPositionLiquidityFailed

```solidity
error GetPositionLiquidityFailed();
```

### GetSqrtPriceX96Failed

```solidity
error GetSqrtPriceX96Failed();
```

### BelowMinRate

```solidity
error BelowMinRate(uint256 liquidity, uint256 minRate, uint256 outputAmount);
```

## Structs
### ZapOutUniswapV3HookData

```solidity
struct ZapOutUniswapV3HookData {
  address[] nftAddresses;
  uint256[] nftIds;
  address[] pools;
  address[] outputTokens;
  uint256[] offsets;
  uint160[] sqrtPLowers;
  uint160[] sqrtPUppers;
  uint256[] minRates;
  address recipient;
}
```

