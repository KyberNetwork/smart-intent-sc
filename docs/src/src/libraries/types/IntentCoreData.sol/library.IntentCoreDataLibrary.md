# IntentCoreDataLibrary
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/libraries/types/IntentCoreData.sol)


## State Variables
### INTENT_CORE_DATA_TYPE_HASH

```solidity
bytes32 constant INTENT_CORE_DATA_TYPE_HASH = keccak256(
  abi.encodePacked(
    'IntentCoreData(address mainAddress,address delegatedAddress,address[] actionContracts,bytes4[] actionSelectors,address hook,bytes hookIntentData)'
  )
);
```


## Functions
### hash


```solidity
function hash(IntentCoreData calldata self) internal pure returns (bytes32);
```

