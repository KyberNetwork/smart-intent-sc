# IntentData
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/libraries/types/IntentData.sol)

Data structure for intent data


```solidity
struct IntentData {
  IntentCoreData coreData;
  TokenData tokenData;
  bytes extraData;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`coreData`|`IntentCoreData`|The core data for the intent|
|`tokenData`|`TokenData`|The token data for the intent|
|`extraData`|`bytes`|The extra data for the intent|

