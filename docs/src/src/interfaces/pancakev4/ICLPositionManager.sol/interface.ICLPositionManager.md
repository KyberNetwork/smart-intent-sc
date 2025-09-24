# ICLPositionManager
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/interfaces/pancakev4/ICLPositionManager.sol)


## Functions
### modifyLiquidities

Unlocks Vault and batches actions for modifying liquidity

*This is the standard entrypoint for the PositionManager*


```solidity
function modifyLiquidities(bytes calldata payload, uint256 deadline) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`payload`|`bytes`|is an encoding of actions, and parameters for those actions|
|`deadline`|`uint256`|is the deadline for the batched actions to be executed|


### modifyLiquiditiesWithoutLock

Batches actions for modifying liquidity without getting a lock from vault

*This must be called by a contract that has already locked the vault*


```solidity
function modifyLiquiditiesWithoutLock(bytes calldata actions, bytes[] calldata params)
  external
  payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`actions`|`bytes`|the actions to perform|
|`params`|`bytes[]`|the parameters to provide for the actions|


### clPoolManager

Get the clPoolManager


```solidity
function clPoolManager() external view returns (ICLPoolManager);
```

### initializePool

Initialize a v4 PCS cl pool


```solidity
function initializePool(PoolKey calldata key, uint160 sqrtPriceX96)
  external
  payable
  returns (int24);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`key`|`PoolKey`|the PoolKey of the pool to initialize|
|`sqrtPriceX96`|`uint160`|the initial sqrtPriceX96 of the pool|


### nextTokenId

Used to get the ID that will be used for the next minted liquidity position


```solidity
function nextTokenId() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|uint256 The next token ID|


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


### positions

Get the detailed information for a specified position


```solidity
function positions(uint256 tokenId)
  external
  view
  returns (
    PoolKey memory poolKey,
    int24 tickLower,
    int24 tickUpper,
    uint128 liquidity,
    uint256 feeGrowthInside0LastX128,
    uint256 feeGrowthInside1LastX128,
    address _subscriber
  );
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|the ERC721 tokenId|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`poolKey`|`PoolKey`|the pool key of the position|
|`tickLower`|`int24`|the lower tick of the position|
|`tickUpper`|`int24`|the upper tick of the position|
|`liquidity`|`uint128`|the liquidity of the position|
|`feeGrowthInside0LastX128`|`uint256`|the fee growth count of token0 since last time updated|
|`feeGrowthInside1LastX128`|`uint256`|the fee growth count of token1 since last time updated|
|`_subscriber`|`address`|the address of the subscriber, if not set, it returns address(0)|


### getPoolAndPositionInfo


```solidity
function getPoolAndPositionInfo(uint256 tokenId)
  external
  view
  returns (PoolKey memory, CLPositionInfo);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|the ERC721 tokenId|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`PoolKey`|poolKey the pool key of the position|
|`<none>`|`CLPositionInfo`|CLPositionInfo a uint256 packed value holding information about the position including the range (tickLower, tickUpper)|


### approve


```solidity
function approve(address to, uint256 tokenId) external;
```

### ownerOf


```solidity
function ownerOf(uint256 _tokenId) external view returns (address);
```

### safeTransferFrom


```solidity
function safeTransferFrom(address _from, address _to, uint256 _tokenId) external payable;
```

### transferFrom


```solidity
function transferFrom(address _from, address _to, uint256 _tokenId) external payable;
```

### poolKeys


```solidity
function poolKeys(bytes25 poolId) external view returns (PoolKey memory);
```

## Events
### MintPosition
Emitted when a new liquidity position is minted


```solidity
event MintPosition(uint256 indexed tokenId);
```

### ModifyLiquidity
Emitted when liquidity is modified


```solidity
event ModifyLiquidity(uint256 indexed tokenId, int256 liquidityChange, BalanceDelta feesAccrued);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|the tokenId of the position that was modified|
|`liquidityChange`|`int256`|the change in liquidity of the position|
|`feesAccrued`|`BalanceDelta`|the fees collected from the liquidity change|

## Errors
### DeadlinePassed
Thrown when the block.timestamp exceeds the user-provided deadline


```solidity
error DeadlinePassed(uint256 deadline);
```

### VaultMustBeUnlocked
Thrown when calling transfer, subscribe, or unsubscribe on CLPositionManager
or batchTransferFrom on BinPositionManager when the vault is locked.

*This is to prevent hooks from being able to trigger actions or notifications at the same time the position is being modified.*


```solidity
error VaultMustBeUnlocked();
```

### InvalidTokenID
Thrown when the token ID is bind to an unexisting pool


```solidity
error InvalidTokenID();
```

### NotApproved
Thrown when the caller is not approved to modify a position


```solidity
error NotApproved(address caller);
```

