# IKSSwapRouterV3
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/interfaces/actions/IKSSwapRouterV3.sol)


## Functions
### swap

Entry point for swapping


```solidity
function swap(SwapParams calldata params) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`params`|`SwapParams`|The parameters for the swap|


### msgSender

Returns the address of who called the swap function


```solidity
function msgSender() external view returns (address);
```

## Structs
### InputTokenData
Contains the additional data for an input token


```solidity
struct InputTokenData {
  bytes permitData;
  address[] feeRecipients;
  uint256[] fees;
  address[] targets;
  uint256[] amounts;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`permitData`|`bytes`|The permit data|
|`feeRecipients`|`address[]`|The fee recipients|
|`fees`|`uint256[]`|The fees, either in bps or absolute value|
|`targets`|`address[]`|The targets to transfer the input token to|
|`amounts`|`uint256[]`|The amounts to transfer to the targets|

### OutputTokenData
Contains the additional data for an output token


```solidity
struct OutputTokenData {
  uint256 minAmount;
  address[] feeRecipients;
  uint256[] fees;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`minAmount`|`uint256`|The minimum output amount|
|`feeRecipients`|`address[]`|The fee recipients|
|`fees`|`uint256[]`|The fees, either in bps or absolute value|

### SwapParams
Contains the parameters for a swap


```solidity
struct SwapParams {
  bytes permit2Data;
  address[] inputTokens;
  uint256[] inputAmounts;
  InputTokenData[] inputData;
  address[] outputTokens;
  OutputTokenData[] outputData;
  address executor;
  bytes executorData;
  address recipient;
  bytes clientData;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`permit2Data`|`bytes`|The data to call permit2 with|
|`inputTokens`|`address[]`|The input tokens|
|`inputAmounts`|`uint256[]`|The input amounts|
|`inputData`|`InputTokenData[]`|The additional data for the input tokens|
|`outputTokens`|`address[]`|The output tokens|
|`outputData`|`OutputTokenData[]`|The additional data for the output tokens|
|`executor`|`address`|The executor to call|
|`executorData`|`bytes`|The data to pass to the executor|
|`recipient`|`address`|The recipient of the output tokens|
|`clientData`|`bytes`|The client data|

