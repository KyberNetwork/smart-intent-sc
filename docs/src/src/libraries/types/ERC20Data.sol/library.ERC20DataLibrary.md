# ERC20DataLibrary
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/libraries/types/ERC20Data.sol)


## State Variables
### ERC20_DATA_TYPE_HASH

```solidity
bytes32 constant ERC20_DATA_TYPE_HASH =
  keccak256(abi.encodePacked('ERC20Data(address token,uint256 amount,bytes permitData)'));
```


## Functions
### hash


```solidity
function hash(ERC20Data calldata self) internal pure returns (bytes32);
```

### collect


```solidity
function collect(
  address token,
  uint256 amount,
  address mainAddress,
  address actionContract,
  uint256 fee,
  bool approvalFlag,
  IKSGenericForwarder forwarder,
  address feeRecipient
) internal;
```

### _forwardApproveInf


```solidity
function _forwardApproveInf(IKSGenericForwarder forwarder, address token, address spender) internal;
```

