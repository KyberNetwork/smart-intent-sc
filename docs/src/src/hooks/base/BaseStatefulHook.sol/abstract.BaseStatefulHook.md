# BaseStatefulHook
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/hooks/base/BaseStatefulHook.sol)

**Inherits:**
[BaseHook](/src/hooks/base/BaseHook.sol/abstract.BaseHook.md)


## State Variables
### whitelistedRouters

```solidity
mapping(address => bool) public whitelistedRouters;
```


## Functions
### constructor


```solidity
constructor(address[] memory initialRouters);
```

### onlyWhitelistedRouter


```solidity
modifier onlyWhitelistedRouter();
```

## Errors
### NonWhitelistedRouter

```solidity
error NonWhitelistedRouter(address router);
```

