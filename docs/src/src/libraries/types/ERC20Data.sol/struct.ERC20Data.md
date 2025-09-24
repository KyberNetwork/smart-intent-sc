# ERC20Data
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/libraries/types/ERC20Data.sol)

Data structure for ERC20 token


```solidity
struct ERC20Data {
  address token;
  uint256 amount;
  bytes permitData;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The address of the ERC20 token|
|`amount`|`uint256`|The amount of the ERC20 token|
|`permitData`|`bytes`|The permit data for the ERC20 token|

