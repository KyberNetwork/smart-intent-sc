# KSSmartIntentRouterAccounting
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/KSSmartIntentRouterAccounting.sol)

**Inherits:**
[KSSmartIntentStorage](/src/KSSmartIntentStorage.sol/abstract.KSSmartIntentStorage.md), ManagementRescuable


## State Variables
### erc20Allowances

```solidity
mapping(bytes32 => mapping(address => uint256)) public erc20Allowances;
```


## Functions
### _approveTokens

Set the tokens' allowances for the intent


```solidity
function _approveTokens(bytes32 intentHash, TokenData calldata tokenData, address mainAddress)
  internal;
```

### _collectTokens

Transfer the tokens to this contract and update the allowances


```solidity
function _collectTokens(
  bytes32 intentHash,
  address mainAddress,
  address actionContract,
  TokenData calldata tokenData,
  ActionData calldata actionData,
  IKSGenericForwarder _forwarder,
  uint256[] memory fees
) internal checkLengths(actionData.erc20Ids.length, actionData.erc20Amounts.length);
```

### _spentAllowance


```solidity
function _spentAllowance(bytes32 intentHash, address token, uint256 amount) internal;
```

### onERC721Received


```solidity
function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4);
```

### supportsInterface


```solidity
function supportsInterface(bytes4 interfaceId) public view override returns (bool);
```

### _checkFlag


```solidity
function _checkFlag(uint256 flag, uint256 index) internal pure returns (bool result);
```

