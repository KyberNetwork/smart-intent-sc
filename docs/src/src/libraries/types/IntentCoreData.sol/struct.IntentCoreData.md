# IntentCoreData
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/libraries/types/IntentCoreData.sol)

Data structure for core components of intent


```solidity
struct IntentCoreData {
  address mainAddress;
  address delegatedAddress;
  address[] actionContracts;
  bytes4[] actionSelectors;
  address hook;
  bytes hookIntentData;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`mainAddress`|`address`|The main address|
|`delegatedAddress`|`address`|The delegated address|
|`actionContracts`|`address[]`|The addresses of the action contracts|
|`actionSelectors`|`bytes4[]`|The selectors of the action functions|
|`hook`|`address`|The address of the hook|
|`hookIntentData`|`bytes`|The intent data for the hook|

