# KSSmartIntentRouter
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/KSSmartIntentRouter.sol)

**Inherits:**
[KSSmartIntentRouterAccounting](/src/KSSmartIntentRouterAccounting.sol/abstract.KSSmartIntentRouterAccounting.md), [KSSmartIntentRouterNonces](/src/KSSmartIntentRouterNonces.sol/abstract.KSSmartIntentRouterNonces.md), ReentrancyGuardTransient, EIP712


## Functions
### constructor


```solidity
constructor(
  address initialAdmin,
  address[] memory initialGuardians,
  address[] memory initialRescuers,
  address[] memory initialActionContracts,
  address _feeRecipient,
  address _forwarder
) ManagementBase(0, initialAdmin);
```

### receive


```solidity
receive() external payable;
```

### hashTypedIntentData

Hash the intent data with EIP712


```solidity
function hashTypedIntentData(IntentData calldata intentData) public view returns (bytes32);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`intentData`|`IntentData`|The intent data|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|hash The hash of the intent data|


### hashTypedActionData

Hash the action data with EIP712


```solidity
function hashTypedActionData(ActionData calldata actionData) public view returns (bytes32);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`actionData`|`ActionData`|The action data|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|hash The hash of the action data|


### updateForwarder

Update the forwarder address


```solidity
function updateForwarder(address newForwarder) public onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newForwarder`|`address`|The new forwarder address|


### _updateForwarder


```solidity
function _updateForwarder(address newForwarder) internal;
```

### updateFeeRecipient

Update the intent fee recipient


```solidity
function updateFeeRecipient(address newFeeRecipient) public onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newFeeRecipient`|`address`|The new intent fee recipient|


### _updateFeeRecipient


```solidity
function _updateFeeRecipient(address newFeeRecipient) internal;
```

### delegate

Delegate the intent to the delegated address


```solidity
function delegate(IntentData calldata intentData) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`intentData`|`IntentData`|The data for the intent|


### revoke

Revoke the delegated intent


```solidity
function revoke(IntentData calldata intentData) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`intentData`|`IntentData`|The intent data to revoke|


### execute

Execute the intent


```solidity
function execute(
  IntentData calldata intentData,
  bytes memory daSignature,
  address guardian,
  bytes memory gdSignature,
  ActionData calldata actionData
) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`intentData`|`IntentData`|The data for the intent|
|`daSignature`|`bytes`|The signature of the delegated address|
|`guardian`|`address`|The address of the guardian|
|`gdSignature`|`bytes`|The signature of the guardian|
|`actionData`|`ActionData`|The data for the action|


### executeWithSignedIntent

Execute the intent with the signed data and main address signature


```solidity
function executeWithSignedIntent(
  IntentData calldata intentData,
  bytes memory maSignature,
  bytes memory daSignature,
  address guardian,
  bytes memory gdSignature,
  ActionData calldata actionData
) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`intentData`|`IntentData`|The data for the intent|
|`maSignature`|`bytes`|The signature of the main address|
|`daSignature`|`bytes`|The signature of the delegated address|
|`guardian`|`address`|The address of the guardian|
|`gdSignature`|`bytes`|The signature of the guardian|
|`actionData`|`ActionData`|The data for the action|


### _delegate


```solidity
function _delegate(IntentData calldata intentData, bytes32 intentHash)
  internal
  checkLengths(intentData.coreData.actionContracts.length, intentData.coreData.actionSelectors.length);
```

### _execute


```solidity
function _execute(
  bytes32 intentHash,
  IntentData calldata intentData,
  bytes memory daSignature,
  address guardian,
  bytes memory gdSignature,
  ActionData calldata actionData
) internal nonReentrant;
```

### _needForwarder


```solidity
function _needForwarder(bytes4 selector) internal view returns (IKSGenericForwarder);
```

### _validateActionData


```solidity
function _validateActionData(
  IntentCoreData calldata coreData,
  bytes memory daSignature,
  address guardian,
  bytes memory gdSignature,
  bytes32 actionHash
) internal view;
```

### _checkIntentStatus


```solidity
function _checkIntentStatus(bytes32 intentHash, IntentStatus expectedStatus) internal view;
```

