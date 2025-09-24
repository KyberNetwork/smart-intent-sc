# ActionDataLibrary
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/libraries/types/ActionData.sol)


## State Variables
### ACTION_DATA_TYPE_HASH

```solidity
bytes32 constant ACTION_DATA_TYPE_HASH = keccak256(
  abi.encodePacked(
    'ActionData(uint256[] erc20Ids,uint256[] erc20Amounts,uint256[] erc721Ids,uint256 approvalFlags,uint256 actionSelectorId,bytes actionCalldata,bytes hookActionData,bytes extraData,uint256 deadline,uint256 nonce)'
  )
);
```


## Functions
### hash


```solidity
function hash(ActionData calldata self) internal pure returns (bytes32);
```

