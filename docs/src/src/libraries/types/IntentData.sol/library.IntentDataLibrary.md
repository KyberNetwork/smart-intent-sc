# IntentDataLibrary
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/libraries/types/IntentData.sol)


## State Variables
### INTENT_DATA_TYPE_HASH

```solidity
bytes32 constant INTENT_DATA_TYPE_HASH = keccak256(
  abi.encodePacked(
    'IntentData(IntentCoreData coreData,TokenData tokenData,bytes extraData)ERC20Data(address token,uint256 amount,bytes permitData)ERC721Data(address token,uint256 tokenId,bytes permitData)IntentCoreData(address mainAddress,address delegatedAddress,address[] actionContracts,bytes4[] actionSelectors,address hook,bytes hookIntentData)TokenData(ERC20Data[] erc20Data,ERC721Data[] erc721Data)'
  )
);
```


## Functions
### hash


```solidity
function hash(IntentData calldata self) internal pure returns (bytes32);
```

