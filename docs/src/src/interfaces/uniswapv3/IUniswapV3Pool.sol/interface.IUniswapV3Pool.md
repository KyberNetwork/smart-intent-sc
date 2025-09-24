# IUniswapV3Pool
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/interfaces/uniswapv3/IUniswapV3Pool.sol)


## Functions
### slot0


```solidity
function slot0()
  external
  view
  returns (
    uint160 sqrtPriceX96,
    int24 tick,
    uint16 observationIndex,
    uint16 observationCardinality,
    uint16 observationCardinalityNext,
    uint256 feeProtocol,
    bool unlocked
  );
```

### feeGrowthGlobal0X128

The fee growth as a Q128.128 fees of token0 collected per unit of liquidity for the entire life of the pool

*This value can overflow the uint256*


```solidity
function feeGrowthGlobal0X128() external view returns (uint256);
```

### feeGrowthGlobal1X128

The fee growth as a Q128.128 fees of token1 collected per unit of liquidity for the entire life of the pool

*This value can overflow the uint256*


```solidity
function feeGrowthGlobal1X128() external view returns (uint256);
```

### protocolFees

The amounts of token0 and token1 that are owed to the protocol

*Protocol fees will never exceed uint128 max in either token*


```solidity
function protocolFees() external view returns (uint128 token0, uint128 token1);
```

### liquidity

The currently in range liquidity available to the pool

*This value has no relationship to the total liquidity across all ticks*


```solidity
function liquidity() external view returns (uint128);
```

### ticks

Look up information about a specific tick in the pool


```solidity
function ticks(int24 tick)
  external
  view
  returns (
    uint128 liquidityGross,
    int128 liquidityNet,
    uint256 feeGrowthOutside0X128,
    uint256 feeGrowthOutside1X128,
    int56 tickCumulativeOutside,
    uint160 secondsPerLiquidityOutsideX128,
    uint32 secondsOutside,
    bool initialized
  );
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tick`|`int24`|The tick to look up|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`liquidityGross`|`uint128`|the total amount of position liquidity that uses the pool either as tick lower or tick upper, liquidityNet how much liquidity changes when the pool price crosses the tick, feeGrowthOutside0X128 the fee growth on the other side of the tick from the current tick in token0, feeGrowthOutside1X128 the fee growth on the other side of the tick from the current tick in token1, tickCumulativeOutside the cumulative tick value on the other side of the tick from the current tick secondsPerLiquidityOutsideX128 the seconds spent per liquidity on the other side of the tick from the current tick, secondsOutside the seconds spent on the other side of the tick from the current tick, initialized Set to true if the tick is initialized, i.e. liquidityGross is greater than 0, otherwise equal to false. Outside values can only be used if the tick is initialized, i.e. if liquidityGross is greater than 0. In addition, these values are only relative and must be used only in comparison to previous snapshots for a specific position.|
|`liquidityNet`|`int128`||
|`feeGrowthOutside0X128`|`uint256`||
|`feeGrowthOutside1X128`|`uint256`||
|`tickCumulativeOutside`|`int56`||
|`secondsPerLiquidityOutsideX128`|`uint160`||
|`secondsOutside`|`uint32`||
|`initialized`|`bool`||


