# ERC721DataLibrary
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/libraries/types/ERC721Data.sol)


## State Variables
### ERC721_DATA_TYPE_HASH

```solidity
bytes32 constant ERC721_DATA_TYPE_HASH =
  keccak256(abi.encodePacked('ERC721Data(address token,uint256 tokenId,bytes permitData)'));
```


## Functions
### hash


```solidity
function hash(ERC721Data calldata self) internal pure returns (bytes32);
```

### collect


```solidity
function collect(
  address token,
  uint256 tokenId,
  address mainAddress,
  address actionContract,
  IKSGenericForwarder forwarder,
  bool approvalFlag
) internal;
```

