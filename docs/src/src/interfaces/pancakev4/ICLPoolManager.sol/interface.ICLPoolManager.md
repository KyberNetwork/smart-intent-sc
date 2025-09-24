# ICLPoolManager
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/interfaces/pancakev4/ICLPoolManager.sol)


## Functions
### updateDynamicLPFee

Updates lp fee for a dyanmic fee pool

*Some of the use case could be:
1) when hook#beforeSwap() is called and hook call this function to update the lp fee
2) For BinPool only, when hook#beforeMint() is called and hook call this function to update the lp fee
3) other use case where the hook might want to on an ad-hoc basis increase/reduce lp fee*


```solidity
function updateDynamicLPFee(PoolKey memory key, uint24 newDynamicLPFee) external;
```

### poolIdToPoolKey

Return PoolKey for a given PoolId


```solidity
function poolIdToPoolKey(PoolId id) external view returns (PoolKey memory key);
```

### getSlot0

Get the current value in slot0 of the given pool


```solidity
function getSlot0(PoolId id)
  external
  view
  returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee);
```

### getLiquidity

Get the current value of liquidity of the given pool


```solidity
function getLiquidity(PoolId id) external view returns (uint128 liquidity);
```

### getLiquidity

Get the current value of liquidity for the specified pool and position


```solidity
function getLiquidity(PoolId id, address owner, int24 tickLower, int24 tickUpper, bytes32 salt)
  external
  view
  returns (uint128 liquidity);
```

### getPoolTickInfo

Get the tick info about a specific tick in the pool


```solidity
function getPoolTickInfo(PoolId id, int24 tick) external view returns (TickInfo memory tickInfo);
```

### getPoolBitmapInfo

Get the tick bitmap info about a specific range (a word range) in the pool


```solidity
function getPoolBitmapInfo(PoolId id, int16 word) external view returns (uint256 tickBitmap);
```

### getFeeGrowthGlobals

Get the fee growth global for the given pool


```solidity
function getFeeGrowthGlobals(PoolId id)
  external
  view
  returns (uint256 feeGrowthGlobal0x128, uint256 feeGrowthGlobal1x128);
```

### initialize

Initialize the state for a given pool ID


```solidity
function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick);
```

### modifyLiquidity

Modify the position for the given pool


```solidity
function modifyLiquidity(
  PoolKey memory key,
  ModifyLiquidityParams memory params,
  bytes calldata hookData
) external returns (BalanceDelta delta, BalanceDelta feeDelta);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`delta`|`BalanceDelta`|The total balance delta of the caller of modifyLiquidity.|
|`feeDelta`|`BalanceDelta`|The balance delta of the fees generated in the liquidity range.|


### swap

Swap against the given pool

*Swapping on low liquidity pools may cause unexpected swap amounts when liquidity available is less than amountSpecified.
Additionally note that if interacting with hooks that have the BEFORE_SWAP_RETURNS_DELTA_FLAG or AFTER_SWAP_RETURNS_DELTA_FLAG
the hook may alter the swap input/output. Integrators should perform checks on the returned swapDelta.*


```solidity
function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
  external
  returns (BalanceDelta delta);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`key`|`PoolKey`|The pool to swap in|
|`params`|`SwapParams`|The parameters for swapping|
|`hookData`|`bytes`|Any data to pass to the callback|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`delta`|`BalanceDelta`|The balance delta of the address swapping|


## Events
### DynamicLPFeeUpdated
Emitted when lp fee is updated

*The event is emitted even if the updated fee value is the same as previous one*


```solidity
event DynamicLPFeeUpdated(PoolId indexed id, uint24 dynamicLPFee);
```

### ModifyLiquidity
Emitted when a liquidity position is modified


```solidity
event ModifyLiquidity(
  PoolId indexed id,
  address indexed sender,
  int24 tickLower,
  int24 tickUpper,
  int256 liquidityDelta,
  bytes32 salt
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`id`|`PoolId`|The abi encoded hash of the pool key struct for the pool that was modified|
|`sender`|`address`|The address that modified the pool|
|`tickLower`|`int24`|The lower tick of the position|
|`tickUpper`|`int24`|The upper tick of the position|
|`liquidityDelta`|`int256`|The amount of liquidity that was added or removed|
|`salt`|`bytes32`|The value used to create a unique liquidity position|

### Swap
Emitted for swaps between currency0 and currency1


```solidity
event Swap(
  PoolId indexed id,
  address indexed sender,
  int128 amount0,
  int128 amount1,
  uint160 sqrtPriceX96,
  uint128 liquidity,
  int24 tick,
  uint24 fee,
  uint16 protocolFee
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`id`|`PoolId`|The abi encoded hash of the pool key struct for the pool that was modified|
|`sender`|`address`|The address that initiated the swap call, and that received the callback|
|`amount0`|`int128`|The delta of the currency0 balance of the pool|
|`amount1`|`int128`|The delta of the currency1 balance of the pool|
|`sqrtPriceX96`|`uint160`|The sqrt(price) of the pool after the swap, as a Q64.96|
|`liquidity`|`uint128`|The liquidity of the pool after the swap|
|`tick`|`int24`|The log base 1.0001 of the price of the pool after the swap|
|`fee`|`uint24`|The fee collected upon every swap in the pool (including protocol fee and LP fee), denominated in hundredths of a bip|
|`protocolFee`|`uint16`|Single direction protocol fee from the swap, also denominated in hundredths of a bip|

### Donate
Emitted when donate happen


```solidity
event Donate(
  PoolId indexed id, address indexed sender, uint256 amount0, uint256 amount1, int24 tick
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`id`|`PoolId`|The abi encoded hash of the pool key struct for the pool that was modified|
|`sender`|`address`|The address that modified the pool|
|`amount0`|`uint256`|The delta of the currency0 balance of the pool|
|`amount1`|`uint256`|The delta of the currency1 balance of the pool|
|`tick`|`int24`|The donated tick|

## Errors
### PoolNotInitialized
Thrown when trying to interact with a non-initialized pool


```solidity
error PoolNotInitialized();
```

### CurrenciesInitializedOutOfOrder
PoolKey must have currencies where address(currency0) < address(currency1)


```solidity
error CurrenciesInitializedOutOfOrder(address currency0, address currency1);
```

### UnauthorizedDynamicLPFeeUpdate
Thrown when a call to updateDynamicLPFee is made by an address that is not the hook,
or on a pool is not a dynamic fee pool.


```solidity
error UnauthorizedDynamicLPFeeUpdate();
```

### PoolManagerMismatch
PoolManagerMismatch is thrown when pool manager specified in the pool key does not match current contract


```solidity
error PoolManagerMismatch();
```

### TickSpacingTooLarge
Pools are limited to type(int16).max tickSpacing in #initialize, to prevent overflow


```solidity
error TickSpacingTooLarge(int24 tickSpacing);
```

### TickSpacingTooSmall
Pools must have a positive non-zero tickSpacing passed to #initialize


```solidity
error TickSpacingTooSmall(int24 tickSpacing);
```

### PoolPaused
Error thrown when add liquidity is called when paused()


```solidity
error PoolPaused();
```

### SwapAmountCannotBeZero
Thrown when trying to swap amount of 0


```solidity
error SwapAmountCannotBeZero();
```

## Structs
### ModifyLiquidityParams

```solidity
struct ModifyLiquidityParams {
  int24 tickLower;
  int24 tickUpper;
  int256 liquidityDelta;
  bytes32 salt;
}
```

### SwapParams

```solidity
struct SwapParams {
  bool zeroForOne;
  int256 amountSpecified;
  uint160 sqrtPriceLimitX96;
}
```

