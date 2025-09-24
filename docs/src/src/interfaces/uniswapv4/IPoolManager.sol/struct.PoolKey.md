# PoolKey
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/interfaces/uniswapv4/IPoolManager.sol)

Returns the key for identifying a pool


```solidity
struct PoolKey {
  address currency0;
  address currency1;
  uint24 fee;
  int24 tickSpacing;
  address hooks;
}
```

