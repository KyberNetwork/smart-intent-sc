# StateLibrary
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/libraries/uniswapv4/StateLibrary.sol)

A helper library to provide state getters that use extsload


## State Variables
### POOLS_SLOT
index of pools mapping in the PoolManager


```solidity
bytes32 public constant POOLS_SLOT = bytes32(uint256(6));
```


### FEE_GROWTH_GLOBAL0_OFFSET
index of feeGrowthGlobal0X128 in Pool.State


```solidity
uint256 public constant FEE_GROWTH_GLOBAL0_OFFSET = 1;
```


### LIQUIDITY_OFFSET
index of liquidity in Pool.State


```solidity
uint256 public constant LIQUIDITY_OFFSET = 3;
```


### TICKS_OFFSET
index of TicksInfo mapping in Pool.State: mapping(int24 => TickInfo) ticks;


```solidity
uint256 public constant TICKS_OFFSET = 4;
```


### TICK_BITMAP_OFFSET
index of tickBitmap mapping in Pool.State


```solidity
uint256 public constant TICK_BITMAP_OFFSET = 5;
```


### POSITIONS_OFFSET
index of Position.State mapping in Pool.State: mapping(bytes32 => Position.State) positions;


```solidity
uint256 public constant POSITIONS_OFFSET = 6;
```


### Q128

```solidity
uint256 public constant Q128 = 1 << 128;
```


## Functions
### computePositionValues


```solidity
function computePositionValues(
  IPoolManager poolManager,
  IPositionManager positionManager,
  uint256 tokenId,
  uint256 liquidityToRemove
)
  internal
  view
  returns (uint256 amount0, uint256 amount1, uint256 unclaimedFee0, uint256 unclaimedFee1);
```

### getFeeGrowthInside


```solidity
function getFeeGrowthInside(
  IPoolManager poolManager,
  bytes32 poolId,
  int24 tickLower,
  int24 tickUpper,
  int24 tickCurrent
) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128);
```

### getPoolId


```solidity
function getPoolId(PoolKey memory poolKey) internal pure returns (bytes32 poolId);
```

### getSlot0

Get Slot0 of the pool: sqrtPriceX96, tick, protocolFee, lpFee

*Corresponds to pools[poolId].slot0*


```solidity
function getSlot0(IPoolManager manager, bytes32 poolId)
  internal
  view
  returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`manager`|`IPoolManager`|The pool manager contract.|
|`poolId`|`bytes32`|The ID of the pool.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`sqrtPriceX96`|`uint160`|The square root of the price of the pool, in Q96 precision.|
|`tick`|`int24`|The current tick of the pool.|
|`protocolFee`|`uint24`|The protocol fee of the pool.|
|`lpFee`|`uint24`|The swap fee of the pool.|


### getPositionInfo

Retrieves the position information of a pool at a specific position ID.

*Corresponds to pools[poolId].positions[positionId]*


```solidity
function getPositionInfo(IPoolManager manager, bytes32 poolId, bytes32 positionId)
  internal
  view
  returns (uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`manager`|`IPoolManager`|The pool manager contract.|
|`poolId`|`bytes32`|The ID of the pool.|
|`positionId`|`bytes32`|The ID of the position.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`liquidity`|`uint128`|The liquidity of the position.|
|`feeGrowthInside0LastX128`|`uint256`|The fee growth inside the position for token0.|
|`feeGrowthInside1LastX128`|`uint256`|The fee growth inside the position for token1.|


### calculatePositionKey

A helper function to calculate the position key


```solidity
function calculatePositionKey(address owner, int24 tickLower, int24 tickUpper, bytes32 salt)
  internal
  pure
  returns (bytes32 positionKey);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`|The address of the position owner|
|`tickLower`|`int24`|the lower tick boundary of the position|
|`tickUpper`|`int24`|the upper tick boundary of the position|
|`salt`|`bytes32`|A unique value to differentiate between multiple positions in the same range, by the same owner. Passed in by the caller.|


### getFeeGrowthGlobals

Retrieves the global fee growth of a pool.

*Corresponds to pools[poolId].feeGrowthGlobal0X128 and pools[poolId].feeGrowthGlobal1X128*


```solidity
function getFeeGrowthGlobals(IPoolManager manager, bytes32 poolId)
  internal
  view
  returns (uint256 feeGrowthGlobal0, uint256 feeGrowthGlobal1);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`manager`|`IPoolManager`|The pool manager contract.|
|`poolId`|`bytes32`|The ID of the pool.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`feeGrowthGlobal0`|`uint256`|The global fee growth for token0.|
|`feeGrowthGlobal1`|`uint256`|The global fee growth for token1.|


### getTickFeeGrowthOutside

Retrieves the fee growth outside a tick range of a pool

*Corresponds to pools[poolId].ticks[tick].feeGrowthOutside0X128 and pools[poolId].ticks[tick].feeGrowthOutside1X128. A more gas efficient version of getTickInfo*


```solidity
function getTickFeeGrowthOutside(IPoolManager manager, bytes32 poolId, int24 tick)
  internal
  view
  returns (uint256 feeGrowthOutside0X128, uint256 feeGrowthOutside1X128);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`manager`|`IPoolManager`|The pool manager contract.|
|`poolId`|`bytes32`|The ID of the pool.|
|`tick`|`int24`|The tick to retrieve fee growth for.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`feeGrowthOutside0X128`|`uint256`|fee growth per unit of liquidity on the _other_ side of this tick (relative to the current tick)|
|`feeGrowthOutside1X128`|`uint256`|fee growth per unit of liquidity on the _other_ side of this tick (relative to the current tick)|


### _getPositionInfoSlot


```solidity
function _getPositionInfoSlot(bytes32 poolId, bytes32 positionId) internal pure returns (bytes32);
```

### _getTickInfoSlot


```solidity
function _getTickInfoSlot(bytes32 poolId, int24 tick) internal pure returns (bytes32);
```

### _getPoolStateSlot


```solidity
function _getPoolStateSlot(bytes32 poolId) internal pure returns (bytes32);
```

### getTickRange


```solidity
function getTickRange(uint256 posInfo) internal pure returns (int24 _tickLower, int24 _tickUpper);
```

