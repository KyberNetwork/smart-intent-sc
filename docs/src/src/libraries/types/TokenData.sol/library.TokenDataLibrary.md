# TokenDataLibrary
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/libraries/types/TokenData.sol)


## State Variables
### TOKEN_DATA_TYPE_HASH

```solidity
bytes32 constant TOKEN_DATA_TYPE_HASH = keccak256(
  abi.encodePacked(
    'TokenData(ERC20Data[] erc20Data,ERC721Data[] erc721Data)ERC20Data(address token,uint256 amount,bytes permitData)ERC721Data(address token,uint256 tokenId,bytes permitData)'
  )
);
```


## Functions
### hash


```solidity
function hash(TokenData calldata self) internal pure returns (bytes32);
```

