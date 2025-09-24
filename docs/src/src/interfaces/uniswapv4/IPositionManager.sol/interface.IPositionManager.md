# IPositionManager
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/interfaces/uniswapv4/IPositionManager.sol)

**Inherits:**
IERC721

Interface for the PositionManager contract


## Functions
### getPositionLiquidity

*this value can be processed as an amount0 and amount1 by using the LiquidityAmounts library*


```solidity
function getPositionLiquidity(uint256 tokenId) external view returns (uint128 liquidity);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|the ERC721 tokenId|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`liquidity`|`uint128`|the position's liquidity, as a liquidityAmount|


### getPoolAndPositionInfo


```solidity
function getPoolAndPositionInfo(uint256 tokenId) external view returns (PoolKey memory, uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|the ERC721 tokenId|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`PoolKey`|PositionInfo a uint256 packed value holding information about the position including the range (tickLower, tickUpper)|
|`<none>`|`uint256`|poolKey the pool key of the position|


### poolManager


```solidity
function poolManager() external view returns (IPoolManager);
```

### modifyLiquidities


```solidity
function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;
```

## Errors
### NotApproved
Thrown when the caller is not approved to modify a position


```solidity
error NotApproved(address caller);
```

### DeadlinePassed
Thrown when the block.timestamp exceeds the user-provided deadline


```solidity
error DeadlinePassed(uint256 deadline);
```

### PoolManagerMustBeLocked
Thrown when calling transfer, subscribe, or unsubscribe when the PoolManager is unlocked.

*This is to prevent hooks from being able to trigger notifications at the same time the position is being modified.*


```solidity
error PoolManagerMustBeLocked();
```

