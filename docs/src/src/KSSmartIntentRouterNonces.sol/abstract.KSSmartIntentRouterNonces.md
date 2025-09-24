# KSSmartIntentRouterNonces
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/KSSmartIntentRouterNonces.sol)

**Inherits:**
[IKSSmartIntentRouter](/src/interfaces/IKSSmartIntentRouter.sol/interface.IKSSmartIntentRouter.md)


## State Variables
### nonces
mapping of nonces consumed by each intent, where a nonce is a single bit on the 256-bit bitmap

*word is at most type(uint248).max*


```solidity
mapping(bytes32 intentHash => mapping(uint256 word => uint256 bitmap)) public nonces;
```


## Functions
### _useUnorderedNonce


```solidity
function _useUnorderedNonce(bytes32 intentHash, uint256 nonce) internal;
```

