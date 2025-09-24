# KSZapOutUniswapV2Hook
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/hooks/zap-out/KSZapOutUniswapV2Hook.sol)

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


## Errors
### InvalidSwapPair

```solidity
error InvalidSwapPair();
```

### BelowMinRate

```solidity
error BelowMinRate(uint256 inputAmount, uint256 outputAmount, uint256 minRate);
```

### OutsidePriceRange

```solidity
error OutsidePriceRange(uint256 priceLower, uint256 priceUpper, uint256 priceCurrent);
```

## Structs
### ZapOutUniswapV2HookData
Data structure for swap validation


```solidity
struct ZapOutUniswapV2HookData {
  address[] srcTokens;
  address[] dstTokens;
  uint256[] priceLowers;
  uint256[] priceUppers;
  uint256[] minRates;
  address recipient;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`srcTokens`|`address[]`|The source tokens|
|`dstTokens`|`address[]`|The destination tokens|
|`priceLowers`|`uint256[]`|The lower price bounds, denominated in 1e18|
|`priceUppers`|`uint256[]`|The upper price bounds, denominated in 1e18|
|`minRates`|`uint256[]`|The minimum rates, denominated in 1e18|
|`recipient`|`address`||

