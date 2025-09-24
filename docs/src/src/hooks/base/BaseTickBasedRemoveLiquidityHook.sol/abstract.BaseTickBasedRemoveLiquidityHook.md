# BaseTickBasedRemoveLiquidityHook
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/hooks/base/BaseTickBasedRemoveLiquidityHook.sol)

**Inherits:**
[BaseConditionalHook](/src/hooks/base/BaseConditionalHook.sol/abstract.BaseConditionalHook.md)


## State Variables
### Q128

```solidity
uint256 public constant Q128 = 1 << 128;
```


### WETH

```solidity
address public immutable WETH;
```


## Functions
### checkTokenLengths


```solidity
modifier checkTokenLengths(ActionData calldata actionData) override;
```

### constructor


```solidity
constructor(address _weth);
```

### beforeExecution

Before execution hook


```solidity
function beforeExecution(bytes32, IntentData calldata intentData, ActionData calldata actionData)
  external
  view
  override
  checkTokenLengths(actionData)
  returns (uint256[] memory, bytes memory beforeExecutionData);
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
|`<none>`|`uint256[]`|fees the amount of fees to be taken|
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


### _validateBeforeExecution


```solidity
function _validateBeforeExecution(IntentData calldata intentData, ActionData calldata actionData)
  internal
  view
  virtual
  returns (bytes memory beforeExecutionData);
```

### _validateAfterExecution


```solidity
function _validateAfterExecution(IntentData calldata intentData, bytes calldata beforeExecutionData)
  internal
  virtual
  returns (
    address[] memory tokens,
    uint256[] memory fees,
    uint256[] memory amounts,
    address recipient
  );
```

### _validateOutput

Validate the output after removing liquidity


```solidity
function _validateOutput(
  OutputValidationParams calldata outputParams,
  PositionInfo calldata positionInfo
) internal view virtual returns (uint256[] memory fees, uint256[] memory userReceived);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`outputParams`|`OutputValidationParams`|The params used to validate output after execution|
|`positionInfo`|`PositionInfo`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`fees`|`uint256[]`|The fees will be charged|
|`userReceived`|`uint256[]`|The amounts of tokens user will receive after removing liquidity|


### _cacheBaseData


```solidity
function _cacheBaseData(
  RemoveLiquidityHookData calldata validationData,
  bytes calldata hookActionData,
  RemoveLiquidityParams memory removeLiqParams,
  OutputValidationParams memory outputParams
) internal view virtual;
```

### _validateConditions


```solidity
function _validateConditions(
  Node[] calldata nodes,
  uint256 fee0Collected,
  uint256 fee1Collected,
  uint256 poolPrice
) internal view virtual;
```

### _validateTokenOwner


```solidity
function _validateTokenOwner(address nftAddress, uint256 nftId, address owner)
  internal
  view
  virtual;
```

### _validateLiquidity


```solidity
function _validateLiquidity(RemoveLiquidityParams calldata removeLiquidityParams)
  internal
  view
  virtual;
```

### _getPositionLiquidity


```solidity
function _getPositionLiquidity(address nftAddress, uint256 nftId)
  internal
  view
  virtual
  returns (uint256 liquidity);
```

### _recordRouterBalances


```solidity
function _recordRouterBalances(address router, address[2] memory tokens)
  internal
  view
  returns (uint256 balance0, uint256 balance1);
```

### _adjustTokens


```solidity
function _adjustTokens(address[2] memory tokens)
  internal
  view
  returns (address[2] memory adjustedTokens);
```

### _buildConditionTree


```solidity
function _buildConditionTree(
  Node[] calldata nodes,
  uint256 fee0Collected,
  uint256 fee1Collected,
  uint256 poolPrice
) internal pure virtual returns (ConditionTree memory conditionTree);
```

### _decodeHookData


```solidity
function _decodeHookData(bytes calldata data)
  internal
  pure
  returns (RemoveLiquidityHookData calldata validationData);
```

### _decodeHookActionData


```solidity
function _decodeHookActionData(bytes calldata data)
  internal
  pure
  virtual
  returns (
    uint256 index,
    uint256 fee0Generated,
    uint256 fee1Generated,
    uint256 liquidity,
    bool wrapOrUnwrap,
    uint256[2] memory intentFeesPercent
  );
```

### _decodeBeforeExecutionData


```solidity
function _decodeBeforeExecutionData(bytes calldata data)
  internal
  pure
  virtual
  returns (
    RemoveLiquidityParams calldata removeLiqParams,
    OutputValidationParams calldata outputParams
  );
```

### _adjustToken


```solidity
function _adjustToken(address token) internal view returns (address adjustedToken);
```

### _toNative


```solidity
function _toNative(address token) internal pure returns (address nativeToken);
```

## Events
### LiquidityRemoved

```solidity
event LiquidityRemoved(address nftAddress, uint256 nftId, uint256 liquidity);
```

## Errors
### InvalidOwner

```solidity
error InvalidOwner();
```

### InvalidLiquidity

```solidity
error InvalidLiquidity();
```

### NotEnoughOutputAmount

```solidity
error NotEnoughOutputAmount();
```

### NotEnoughFeesReceived

```solidity
error NotEnoughFeesReceived();
```

## Structs
### RemoveLiquidityHookData
Data structure for remove liquidity validation


```solidity
struct RemoveLiquidityHookData {
  address[] nftAddresses;
  uint256[] nftIds;
  Node[][] nodes;
  uint256[] maxFees;
  address recipient;
  bytes additionalData;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`nftAddresses`|`address[]`|The NFT addresses|
|`nftIds`|`uint256[]`|The NFT IDs|
|`nodes`|`Node[][]`|The nodes of conditions (used to build the condition tree)|
|`maxFees`|`uint256[]`|The max fee percents for each output token (1e6 = 100%), [128 bits token0 max fee, 128 bits token1 max fee]|
|`recipient`|`address`|The recipient|
|`additionalData`|`bytes`|The additional data|

### RemoveLiquidityParams
Data structure for remove liquidity params


```solidity
struct RemoveLiquidityParams {
  uint256 index;
  uint256 liquidityToRemove;
  bool wrapOrUnwrap;
  address recipient;
  uint160 sqrtPriceX96;
  int24 currentTick;
  PositionInfo positionInfo;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`index`|`uint256`|The index of validation data in RemoveLiquidityHookData struct|
|`liquidityToRemove`|`uint256`|The liquidity to remove|
|`wrapOrUnwrap`|`bool`|Whether to wrap or unwrap the tokens after removing liquidity|
|`recipient`|`address`|The recipient of the output tokens|
|`sqrtPriceX96`|`uint160`||
|`currentTick`|`int24`|The current tick of the pool|
|`positionInfo`|`PositionInfo`|The position info of the NFT|

### OutputValidationParams
Data structure for output validation params


```solidity
struct OutputValidationParams {
  address router;
  uint256[2] balancesBefore;
  uint256[2] maxFees;
  uint256[2] intentFeesPercent;
  address[2] tokens;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`router`|`address`|The router address that receives the output tokens after removing liquidity|
|`balancesBefore`|`uint256[2]`|The token0, token1 balances of the router before removing liquidity|
|`maxFees`|`uint256[2]`|The max fee percents for each output token (1e6 = 100%)|
|`intentFeesPercent`|`uint256[2]`|The intent fees percents for each output token (1e6 = 100%)|
|`tokens`|`address[2]`|The token0, token1 of the pool|

### PositionInfo
Data structure for position info


```solidity
struct PositionInfo {
  address nftAddress;
  uint256 nftId;
  uint256 liquidity;
  int24[2] ticks;
  uint256[2] feesGrowthInsideLast;
  uint256[2] feesGenerated;
  uint256[2] amounts;
  uint256[2] unclaimedFees;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The NFT address|
|`nftId`|`uint256`|The NFT ID|
|`liquidity`|`uint256`|The liquidity of the position before removing liquidity|
|`ticks`|`int24[2]`|Position tick range [tickLower, tickUpper]|
|`feesGrowthInsideLast`|`uint256[2]`|The fees growth count of token0 and token1 since last time updated|
|`feesGenerated`|`uint256[2]`|The fees generated of token0 and token1|
|`amounts`|`uint256[2]`|The expected amounts of tokens received from removing the specified liquidity|
|`unclaimedFees`|`uint256[2]`|The unclaimed fees of the position|

