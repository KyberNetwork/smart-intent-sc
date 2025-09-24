# IKSSwapRouterV2
[Git Source](https://github.com/KyberNetwork/smart-intent-sc/blob/93222d2e196228c709f4e585edadefb65277a3e4/src/interfaces/actions/IKSSwapRouterV2.sol)


## Functions
### swapGeneric


```solidity
function swapGeneric(SwapExecutionParams memory)
  external
  payable
  returns (uint256 returnAmount, uint256 gasUsed);
```

### swap


```solidity
function swap(SwapExecutionParams memory)
  external
  payable
  returns (uint256 returnAmount, uint256 gasUsed);
```

### swapSimpleMode


```solidity
function swapSimpleMode(
  address caller,
  SwapDescriptionV2 memory desc,
  bytes calldata executorData,
  bytes calldata clientData
) external returns (uint256 returnAmount, uint256 gasUsed);
```

## Structs
### SwapDescriptionV2

```solidity
struct SwapDescriptionV2 {
  address srcToken;
  address dstToken;
  address[] srcReceivers;
  uint256[] srcAmounts;
  address[] feeReceivers;
  uint256[] feeAmounts;
  address dstReceiver;
  uint256 amount;
  uint256 minReturnAmount;
  uint256 flags;
  bytes permit;
}
```

### SwapExecutionParams

```solidity
struct SwapExecutionParams {
  address callTarget;
  address approveTarget;
  bytes targetData;
  SwapDescriptionV2 desc;
  bytes clientData;
}
```

