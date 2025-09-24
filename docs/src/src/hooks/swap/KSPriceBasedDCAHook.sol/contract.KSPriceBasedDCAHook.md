# KSPriceBasedDCAHook
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/hooks/swap/KSPriceBasedDCAHook.sol)

**Inherits:**
[BaseStatefulHook](/src/hooks/base/BaseStatefulHook.sol/abstract.BaseStatefulHook.md)


## State Variables
### latestSwap

```solidity
mapping(bytes32 => uint256) public latestSwap;
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
  view
  override
  onlyWhitelistedRouter
  returns (address[] memory, uint256[] memory, uint256[] memory, address);
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
### ExceedNumSwaps

```solidity
error ExceedNumSwaps(uint256 numSwaps, uint256 swapNo);
```

### InvalidAmountIn

```solidity
error InvalidAmountIn(uint256 amountIn, uint256 actualAmountIn);
```

### InvalidAmountOut

```solidity
error InvalidAmountOut(uint256 minAmountOut, uint256 maxAmountOut, uint256 actualAmountOut);
```

### SwapAlreadyExecuted

```solidity
error SwapAlreadyExecuted();
```

## Structs
### DCAHookData
Data structure for dca hook


```solidity
struct DCAHookData {
  address srcToken;
  address dstToken;
  uint256[] amountIns;
  uint256[] amountOutLimits;
  address recipient;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`srcToken`|`address`||
|`dstToken`|`address`|The destination token|
|`amountIns`|`uint256[]`||
|`amountOutLimits`|`uint256[]`||
|`recipient`|`address`||

