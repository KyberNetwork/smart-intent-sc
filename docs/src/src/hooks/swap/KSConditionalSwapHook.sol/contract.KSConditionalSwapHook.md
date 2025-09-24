# KSConditionalSwapHook
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/hooks/swap/KSConditionalSwapHook.sol)

**Inherits:**
[BaseStatefulHook](/src/hooks/base/BaseStatefulHook.sol/abstract.BaseStatefulHook.md), [BaseConditionalHook](/src/hooks/base/BaseConditionalHook.sol/abstract.BaseConditionalHook.md)


## State Variables
### DENOMINATOR

```solidity
uint256 public constant DENOMINATOR = 1e18;
```


### swapRecord
Tracks swap execution counts for each condition to enforce swap limits

*Maps intentHash -> intentIndex -> packedIndexes -> packedCounts
Each uint256 stores up to 32 uint8 swap counts (8 bits each), indexed by swapIndexes / 32
Individual counts are extracted using bit shifts based on swapIndexes % 32*


```solidity
mapping(
  bytes32 intentHash
    => mapping(uint256 intentIndex => mapping(uint256 swapIndexes => uint256 swapCount))
) public swapRecord;
```


## Functions
### constructor


```solidity
constructor(address[] memory initialRouters) BaseStatefulHook(initialRouters);
```

### checkTokenLengths


```solidity
modifier checkTokenLengths(ActionData calldata actionData) override;
```

### beforeExecution

Before execution hook


```solidity
function beforeExecution(
  bytes32 intentHash,
  IntentData calldata intentData,
  ActionData calldata actionData
)
  external
  override
  onlyWhitelistedRouter
  checkTokenLengths(actionData)
  returns (uint256[] memory fees, bytes memory beforeExecutionData);
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
  bytes32,
  IntentData calldata intentData,
  bytes calldata beforeExecutionData,
  bytes calldata
)
  external
  override
  onlyWhitelistedRouter
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
|`<none>`|`bytes32`||
|`intentData`|`IntentData`|the intent data|
|`beforeExecutionData`|`bytes`|the data returned from `beforeExecution`|
|`<none>`|`bytes`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokens`|`address[]`|the tokens to be taken fees from and to be returned to the recipient|
|`fees`|`uint256[]`|the fees to be taken|
|`amounts`|`uint256[]`|the amounts of the tokens to be returned to the recipient|
|`recipient`|`address`|the address of the recipient|


### getSwapExecutionCount

Gets the number of times a specific swap condition has been executed


```solidity
function getSwapExecutionCount(bytes32 intentHash, uint256 intentIndex, uint256 conditionIndex)
  public
  view
  returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`intentHash`|`bytes32`|The hash of the intent|
|`intentIndex`|`uint256`|The index of the specific intent|
|`conditionIndex`|`uint256`|The index of the swap condition to check|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The number of times this condition has been executed|


### _validateSwapCondition


```solidity
function _validateSwapCondition(
  SwapCondition[] calldata swapCondition,
  mapping(uint256 swapIndexes => uint256 swapCounts) storage record,
  uint256 price,
  uint256 amountIn,
  uint256 srcFeePercent,
  uint256 dstFeePercent
) internal;
```

### _increaseByOne

Increments swap count for a specific condition index

*Uses bit manipulation to efficiently store counts in packed format*


```solidity
function _increaseByOne(
  mapping(uint256 packedIndexes => uint256 packedValues) storage record,
  uint8 index,
  uint8 limit
) internal returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`record`|`mapping(uint256 packedIndexes => uint256 packedValues)`|Storage mapping containing packed swap counts|
|`index`|`uint8`|The condition index to increment|
|`limit`|`uint8`|Maximum allowed swaps for this condition|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|success True if increment was successful (within limit), false otherwise|


### _getRecipientBalance


```solidity
function _getRecipientBalance(address tokenOut, address recipient, uint256 feePercent)
  internal
  view
  returns (uint256);
```

### _decodeSwapCondition


```solidity
function _decodeSwapCondition(bytes calldata data)
  internal
  pure
  returns (SwapCondition calldata swapCondition);
```

### _decodeHookData


```solidity
function _decodeHookData(bytes calldata data)
  internal
  pure
  returns (SwapHookData calldata hookData);
```

### _decodeAndValidateHookActionData


```solidity
function _decodeAndValidateHookActionData(bytes calldata data, SwapHookData calldata swapHookData)
  internal
  view
  returns (uint256 index, uint256 intentSrcFee, uint256 intentDstFee);
```

### _decodeBeforeExecutionData


```solidity
function _decodeBeforeExecutionData(bytes calldata data)
  internal
  pure
  returns (SwapValidationData calldata validationData);
```

## Errors
### InvalidTokenIn

```solidity
error InvalidTokenIn(address tokenIn, address actualTokenIn);
```

### AmountInMismatch

```solidity
error AmountInMismatch(uint256 amountIn, uint256 actualAmountIn);
```

### InvalidSwap

```solidity
error InvalidSwap();
```

## Structs
### SwapHookData
Data structure for conditional swap


```solidity
struct SwapHookData {
  SwapCondition[][] swapConditions;
  address[] srcTokens;
  address[] dstTokens;
  address recipient;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`swapConditions`|`SwapCondition[][]`|The swap conditions, a swap will be executed if one of the conditions is met|
|`srcTokens`|`address[]`|The source tokens|
|`dstTokens`|`address[]`|The destination tokens|
|`recipient`|`address`|The recipient of the destination token|

### SwapCondition
The limit of swap executions that can be performed for a swap info


```solidity
struct SwapCondition {
  uint8 swapLimit;
  uint256 timeLimits;
  uint256 amountInLimits;
  uint256 maxFees;
  uint256 priceLimits;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`swapLimit`|`uint8`|The maximum number of times the swap can be executed|
|`timeLimits`|`uint256`|The limits of the swap time (minTime 128bits, maxTime 128bits)|
|`amountInLimits`|`uint256`|The limits of the swap amount (minAmountIn 128bits, maxAmountIn 128bits)|
|`maxFees`|`uint256`|The max fees (srcFee 128bits, dstFee 128bits)|
|`priceLimits`|`uint256`|The limits of price (tokenOut/tokenIn denominated by 1e18) (minPrice 128bits, maxPrice 128bits)|

### SwapValidationData

```solidity
struct SwapValidationData {
  SwapCondition[] swapConditions;
  bytes32 intentHash;
  uint256 intentIndex;
  address tokenIn;
  address tokenOut;
  uint256 amountIn;
  uint256 recipientBalanceBefore;
  uint256 swapperBalanceBefore;
  uint256 srcFeePercent;
  uint256 dstFeePercent;
  address recipient;
}
```

