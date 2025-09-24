# IKSZapRouter
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/interfaces/actions/IKSZapRouter.sol)


## Functions
### zap

collect token, execute and validate zap


```solidity
function zap(ZapDescription calldata _desc, ZapExecutionData calldata _exe)
  external
  payable
  returns (bytes memory zapResults);
```

## Structs
### ZapDescription
*Contains general data for zapping and validation*


```solidity
struct ZapDescription {
  uint16 zapFlags;
  bytes srcInfo;
  bytes zapInfo;
  bytes extraData;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`zapFlags`|`uint16`|packed value of dexType (uint8) | srcType (uint8)|
|`srcInfo`|`bytes`|src position info|
|`zapInfo`|`bytes`|extra info, depends on each dex type|
|`extraData`|`bytes`|extra data to be used for validation|

### ZapExecutionData
*Contains execution data for zapping*


```solidity
struct ZapExecutionData {
  address validator;
  address executor;
  uint32 deadline;
  bytes executorData;
  bytes clientData;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`validator`|`address`|validator address, must be whitelisted one|
|`executor`|`address`|zap executor address, must be whitelisted one|
|`deadline`|`uint32`|make sure the request is not expired yet|
|`executorData`|`bytes`|data for zap execution|
|`clientData`|`bytes`|for events and tracking purposes|

