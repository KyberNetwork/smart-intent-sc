# PriceCondition
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/hooks/base/BaseConditionalHook.sol)


```solidity
struct PriceCondition {
  uint256 minPrice;
  uint256 maxPrice;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`minPrice`|`uint256`|the minimum price of the token (would be in sqrtPriceX96 if uni v3 pool type)|
|`maxPrice`|`uint256`|the maximum price of the token (would be in sqrtPriceX96 if uni v3 pool type)|

