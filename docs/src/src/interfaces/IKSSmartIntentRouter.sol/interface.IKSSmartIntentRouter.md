# IKSSmartIntentRouter
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/interfaces/IKSSmartIntentRouter.sol)


## Functions
### delegate

Delegate the intent to the delegated address


```solidity
function delegate(IntentData calldata intentData) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`intentData`|`IntentData`|The data for the intent|


### revoke

Revoke the delegated intent


```solidity
function revoke(IntentData memory intentData) external;
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
) external;
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
) external;
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


### erc20Allowances

Return the ERC20 allowance for a specific intent


```solidity
function erc20Allowances(bytes32 intentHash, address token)
  external
  view
  returns (uint256 allowance);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`intentHash`|`bytes32`|The hash of the intent|
|`token`|`address`|The address of the ERC20 token|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`allowance`|`uint256`|The allowance for the specified token|


### updateForwarder

Update the forwarder address


```solidity
function updateForwarder(address newForwarder) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newForwarder`|`address`|The new forwarder address|


### updateFeeRecipient

Update the intent fee recipient


```solidity
function updateFeeRecipient(address newFeeRecipient) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newFeeRecipient`|`address`|The new intent fee recipient|


### hashTypedIntentData

Hash the intent data with EIP712


```solidity
function hashTypedIntentData(IntentData calldata intentData) external view returns (bytes32);
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
function hashTypedActionData(ActionData calldata actionData) external view returns (bytes32);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`actionData`|`ActionData`|The action data|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|hash The hash of the action data|


### nonces

mapping of nonces consumed by each intent, where a nonce is a single bit on the 256-bit bitmap

*word is at most type(uint248).max*


```solidity
function nonces(bytes32 intentHash, uint256 word) external view returns (uint256 bitmap);
```

## Events
### UpdateForwarder
Emitted when the forwarder is updated


```solidity
event UpdateForwarder(address newForwarder);
```

### UpdateFeeRecipient

```solidity
event UpdateFeeRecipient(address feeRecipient);
```

### DelegateIntent
Emitted when an intent is delegated


```solidity
event DelegateIntent(
  address indexed mainAddress, address indexed delegatedAddress, IntentData intentData
);
```

### RevokeIntent
Emitted when an intent is revoked


```solidity
event RevokeIntent(bytes32 indexed intentHash);
```

### ExecuteIntent
Emitted when an intent is executed


```solidity
event ExecuteIntent(bytes32 indexed intentHash, ActionData actionData, bytes actionResult);
```

### UseNonce
Emitted when a nonce is consumed


```solidity
event UseNonce(bytes32 indexed intentHash, uint256 nonce);
```

### ExtraData
Emitted when extra data is set


```solidity
event ExtraData(bytes32 indexed intentHash, bytes extraData);
```

## Errors
### NotMainAddress
Thrown when the caller is not the main address


```solidity
error NotMainAddress();
```

### ActionExpired
Thrown when the action is expired


```solidity
error ActionExpired();
```

### IntentNotDelegated
Thrown when the intent has not been delegated


```solidity
error IntentNotDelegated();
```

### IntentDelegated
Thrown when the intent has already been delegated


```solidity
error IntentDelegated();
```

### IntentRevoked
Thrown when the intent has already been revoked


```solidity
error IntentRevoked();
```

### InvalidMainAddressSignature
Thrown when the signature is not from the main address


```solidity
error InvalidMainAddressSignature();
```

### InvalidDelegatedAddressSignature
Thrown when the signature is not from the session wallet


```solidity
error InvalidDelegatedAddressSignature();
```

### InvalidGuardianSignature
Thrown when the signature is not from the guardian


```solidity
error InvalidGuardianSignature();
```

### InvalidActionSelectorId
Thrown when the action contract and selector not found in intent


```solidity
error InvalidActionSelectorId(uint256 actionSelectorId);
```

### NonceAlreadyUsed
Thrown when a nonce has already been used


```solidity
error NonceAlreadyUsed(bytes32 intentHash, uint256 nonce);
```

### ERC20InsufficientIntentAllowance
Thrown when collecting more than the intent allowance for ERC20


```solidity
error ERC20InsufficientIntentAllowance(
  bytes32 intentHash, address token, uint256 allowance, uint256 needed
);
```

## Enums
### IntentStatus

```solidity
enum IntentStatus {
  NOT_DELEGATED,
  DELEGATED,
  REVOKED
}
```

