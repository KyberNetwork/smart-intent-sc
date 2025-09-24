# IUniswapV3PM
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/interfaces/uniswapv3/IUniswapV3PM.sol)

**Inherits:**
IERC721


## Functions
### multicall


```solidity
function multicall(bytes[] calldata data) external payable returns (bytes[] memory results);
```

### unwrapWETH9

Unwraps the contract's WETH9 balance and sends it to recipient as ETH.

*The amountMinimum parameter prevents malicious contracts from stealing WETH9 from users.*


```solidity
function unwrapWETH9(uint256 amountMinimum, address recipient) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amountMinimum`|`uint256`|The minimum amount of WETH9 to unwrap|
|`recipient`|`address`|The address receiving ETH|


### sweepToken

Transfers the full amount of a token held by this contract to recipient

*The amountMinimum parameter prevents malicious contracts from stealing the token from users*


```solidity
function sweepToken(address token, uint256 amountMinimum, address recipient) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The contract address of the token which will be transferred to `recipient`|
|`amountMinimum`|`uint256`|The minimum amount of token required for a transfer|
|`recipient`|`address`|The destination address of the token|


### decreaseLiquidity

Decreases the amount of liquidity in a position and accounts it to the position


```solidity
function decreaseLiquidity(DecreaseLiquidityParams calldata params)
  external
  payable
  returns (uint256 amount0, uint256 amount1);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`params`|`DecreaseLiquidityParams`|tokenId The ID of the token for which liquidity is being decreased, amount The amount by which liquidity will be decreased, amount0Min The minimum amount of token0 that should be accounted for the burned liquidity, amount1Min The minimum amount of token1 that should be accounted for the burned liquidity, deadline The time by which the transaction must be included to effect the change|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amount0`|`uint256`|The amount of token0 accounted to the position's tokens owed|
|`amount1`|`uint256`|The amount of token1 accounted to the position's tokens owed|


### positions


```solidity
function positions(uint256 tokenId)
  external
  view
  returns (
    uint96 nonce,
    address operator,
    address token0,
    address token1,
    uint24 fee,
    int24 tickLower,
    int24 tickUpper,
    uint128 liquidity,
    uint256 feeGrowthInside0LastX128,
    uint256 feeGrowthInside1LastX128,
    uint128 tokensOwed0,
    uint128 tokensOwed1
  );
```

### collect

Collects up to a maximum amount of fees owed to a specific position to the recipient


```solidity
function collect(CollectParams calldata params)
  external
  payable
  returns (uint256 amount0, uint256 amount1);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`params`|`CollectParams`|tokenId The ID of the NFT for which tokens are being collected, recipient The account that should receive the tokens, amount0Max The maximum amount of token0 to collect, amount1Max The maximum amount of token1 to collect|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amount0`|`uint256`|The amount of fees collected in token0|
|`amount1`|`uint256`|The amount of fees collected in token1|


### factory


```solidity
function factory() external view returns (address);
```

## Structs
### DecreaseLiquidityParams

```solidity
struct DecreaseLiquidityParams {
  uint256 tokenId;
  uint128 liquidity;
  uint256 amount0Min;
  uint256 amount1Min;
  uint256 deadline;
}
```

### CollectParams

```solidity
struct CollectParams {
  uint256 tokenId;
  address recipient;
  uint128 amount0Max;
  uint128 amount1Max;
}
```

