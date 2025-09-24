# PoolKey
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/interfaces/pancakev4/Types.sol)

Returns the key for identifying a pool


```solidity
struct PoolKey {
  address currency0;
  address currency1;
  address hooks;
  address poolManager;
  uint24 fee;
  bytes32 parameters;
}
```

