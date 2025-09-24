# IPoolManager
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/interfaces/uniswapv4/IPoolManager.sol)

Interface for the PoolManager


## Functions
### extsload

Called by external contracts to access granular pool state


```solidity
function extsload(bytes32 slot) external view returns (bytes32 value);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`slot`|`bytes32`|Key of slot to sload|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`value`|`bytes32`|The value of the slot as bytes32|


### extsload

Called by external contracts to access granular pool state


```solidity
function extsload(bytes32 startSlot, uint256 nSlots)
  external
  view
  returns (bytes32[] memory values);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`startSlot`|`bytes32`|Key of slot to start sloading from|
|`nSlots`|`uint256`|Number of slots to load into return value|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`values`|`bytes32[]`|List of loaded values.|


### extsload

Called by external contracts to access sparse pool state


```solidity
function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory values);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`slots`|`bytes32[]`|List of slots to SLOAD from.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`values`|`bytes32[]`|List of loaded values.|


### exttload

Called by external contracts to access transient storage of the contract


```solidity
function exttload(bytes32 slot) external view returns (bytes32 value);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`slot`|`bytes32`|Key of slot to tload|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`value`|`bytes32`|The value of the slot as bytes32|


### exttload

Called by external contracts to access sparse transient pool state


```solidity
function exttload(bytes32[] calldata slots) external view returns (bytes32[] memory values);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`slots`|`bytes32[]`|List of slots to tload|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`values`|`bytes32[]`|List of loaded values|


## Errors
### CurrencyNotSettled
Thrown when a currency is not netted out after the contract is unlocked


```solidity
error CurrencyNotSettled();
```

### PoolNotInitialized
Thrown when trying to interact with a non-initialized pool


```solidity
error PoolNotInitialized();
```

### AlreadyUnlocked
Thrown when unlock is called, but the contract is already unlocked


```solidity
error AlreadyUnlocked();
```

### ManagerLocked
Thrown when a function is called that requires the contract to be unlocked, but it is not


```solidity
error ManagerLocked();
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

### CurrenciesOutOfOrderOrEqual
PoolKey must have currencies where address(currency0) < address(currency1)


```solidity
error CurrenciesOutOfOrderOrEqual(address currency0, address currency1);
```

### UnauthorizedDynamicLPFeeUpdate
Thrown when a call to updateDynamicLPFee is made by an address that is not the hook,
or on a pool that does not have a dynamic swap fee.


```solidity
error UnauthorizedDynamicLPFeeUpdate();
```

### SwapAmountCannotBeZero
Thrown when trying to swap amount of 0


```solidity
error SwapAmountCannotBeZero();
```

### NonzeroNativeValue
Thrown when native currency is passed to a non native settlement


```solidity
error NonzeroNativeValue();
```

### MustClearExactPositiveDelta
Thrown when `clear` is called with an amount that is not exactly equal to the open currency delta.


```solidity
error MustClearExactPositiveDelta();
```

