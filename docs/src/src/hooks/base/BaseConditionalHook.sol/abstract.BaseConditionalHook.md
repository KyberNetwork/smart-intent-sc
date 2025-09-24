# BaseConditionalHook
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/hooks/base/BaseConditionalHook.sol)

**Inherits:**
[BaseHook](/src/hooks/base/BaseHook.sol/abstract.BaseHook.md), [IKSConditionalHook](/src/interfaces/hooks/IKSConditionalHook.sol/interface.IKSConditionalHook.md)


## State Variables
### PRICE_BASED

```solidity
ConditionType public constant PRICE_BASED = ConditionType.wrap(keccak256('PRICE_BASED'));
```


### TIME_BASED

```solidity
ConditionType public constant TIME_BASED = ConditionType.wrap(keccak256('TIME_BASED'));
```


### YIELD_BASED

```solidity
ConditionType public constant YIELD_BASED = ConditionType.wrap(keccak256('YIELD_BASED'));
```


### PRECISION

```solidity
uint256 public constant PRECISION = 1_000_000;
```


### Q96

```solidity
uint256 public constant Q96 = 1 << 96;
```


## Functions
### validateConditionTree

Validates a condition tree starting from the specified root node

*Reverts with ConditionsNotMet() if the conditions are not met*


```solidity
function validateConditionTree(ConditionTree calldata tree, uint256 curIndex) external view virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tree`|`ConditionTree`||
|`curIndex`|`uint256`||


### evaluateCondition


```solidity
function evaluateCondition(Condition calldata condition, bytes calldata additionalData)
  public
  view
  virtual
  returns (bool isSatisfied);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`condition`|`Condition`|the condition to be evaluated|
|`additionalData`|`bytes`|the additional data to be used for evaluation|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`isSatisfied`|`bool`|true if the condition is met, false otherwise|


### _evaluateTimeCondition

helper function to evaluate time condition


```solidity
function _evaluateTimeCondition(Condition calldata condition) internal view virtual returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`condition`|`Condition`|the condition to evaluate|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|true if the condition is satisfied, false otherwise|


### _evaluatePriceCondition

helper function to evaluate price condition


```solidity
function _evaluatePriceCondition(Condition calldata condition, bytes calldata additionalData)
  internal
  pure
  virtual
  returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`condition`|`Condition`|the price condition to evaluate|
|`additionalData`|`bytes`|the abi encoded data of the current price|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|true if the condition is satisfied, false otherwise|


### _evaluateYieldCondition

helper function to evaluate whether the yield condition is satisfied

*Calculates yield as: (fees_in_token0_terms) / (initial_amounts_in_token0_terms)*


```solidity
function _evaluateYieldCondition(Condition calldata condition, bytes calldata additionalData)
  internal
  pure
  virtual
  returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`condition`|`Condition`|The yield condition containing target yield and initial amounts|
|`additionalData`|`bytes`|Encoded fee0, fee1, and poolPrice (sqrtPriceX96 if uni v3 pool type) values|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|true if actual yield >= target yield, false otherwise|


### _convertToken1ToToken0

Converts token1 amount to equivalent token0 amount using current price

*formula: amount0 = amount1 * Q192 / sqrtPriceX96^2*


```solidity
function _convertToken1ToToken0(uint256 sqrtPriceX96, uint256 amount1)
  internal
  pure
  virtual
  returns (uint256 amount0);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sqrtPriceX96`|`uint256`|The pool's sqrt price|
|`amount1`|`uint256`|Amount of token1 to convert|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amount0`|`uint256`|Equivalent amount in token0 terms|


### _decodePriceCondition


```solidity
function _decodePriceCondition(bytes calldata data)
  internal
  pure
  returns (PriceCondition calldata priceCondition);
```

### _decodeTimeCondition


```solidity
function _decodeTimeCondition(bytes calldata data)
  internal
  pure
  returns (TimeCondition calldata timeCondition);
```

### _decodeYieldCondition


```solidity
function _decodeYieldCondition(bytes calldata data)
  internal
  pure
  returns (YieldCondition calldata yieldCondition);
```

## Errors
### WrongConditionType

```solidity
error WrongConditionType();
```

