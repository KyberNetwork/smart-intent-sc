# ERC721Data
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/libraries/types/ERC721Data.sol)

Data structure for ERC721 token


```solidity
struct ERC721Data {
  address token;
  uint256 tokenId;
  bytes permitData;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The address of the ERC721 token|
|`tokenId`|`uint256`|The ID of the ERC721 token|
|`permitData`|`bytes`|The permit data for the ERC721 token|

