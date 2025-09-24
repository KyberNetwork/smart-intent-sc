# KSSmartIntentStorage
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/KSSmartIntentStorage.sol)

**Inherits:**
[IKSSmartIntentRouter](/src/interfaces/IKSSmartIntentRouter.sol/interface.IKSSmartIntentRouter.md)


## State Variables
### ACTION_CONTRACT_ROLE

```solidity
bytes32 internal constant ACTION_CONTRACT_ROLE = keccak256('ACTION_CONTRACT_ROLE');
```


### intentStatuses

```solidity
mapping(bytes32 => IntentStatus) internal intentStatuses;
```


### forwarder

```solidity
IKSGenericForwarder internal forwarder;
```


### feeRecipient

```solidity
address internal feeRecipient;
```


