# ActionData
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/libraries/types/ActionData.sol)

Data structure for action


```solidity
struct ActionData {
  uint256[] erc20Ids;
  uint256[] erc20Amounts;
  uint256[] erc721Ids;
  uint256 approvalFlags;
  uint256 actionSelectorId;
  bytes actionCalldata;
  bytes hookActionData;
  bytes extraData;
  uint256 deadline;
  uint256 nonce;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`erc20Ids`|`uint256[]`|The IDs of the ERC20 tokens in the intent data|
|`erc20Amounts`|`uint256[]`|The amounts of the ERC20 tokens|
|`erc721Ids`|`uint256[]`|The IDs of the ERC721 tokens in the intent data|
|`approvalFlags`|`uint256`|The approval flags for the tokens|
|`actionSelectorId`|`uint256`|The ID of the action selector|
|`actionCalldata`|`bytes`|The calldata for the action|
|`hookActionData`|`bytes`|The action data for the hook|
|`extraData`|`bytes`|The extra data for the action|
|`deadline`|`uint256`|The deadline for the action|
|`nonce`|`uint256`|The nonce for the action|

