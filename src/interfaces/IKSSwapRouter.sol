// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IKSSwapRouter {
  struct SwapDescriptionV2 {
    address srcToken;
    address dstToken;
    address[] srcReceivers; // addresses receiving srcToken to execute swap (amount only for swapping, not included fee receivers as version 1)
    uint256[] srcAmounts; // amounts sent to srcReceivers
    address[] feeReceivers; // fee receivers
    uint256[] feeAmounts; // fee amounts, coulbd be in absolute value or in bps
    address dstReceiver; // address receiving dstToken
    uint256 amount; // the total amount that caller spends
    uint256 minReturnAmount; // min returned amount to dstReceiver
    uint256 flags; // control flags use for router
    bytes permit; // ERC-20 permit data
  }

  struct SwapExecutionParams {
    address callTarget; // address to call to execute swap
    address approveTarget; // (optional) the address to allowed to spend Router's fund, could be used for function swapGeneric
    bytes targetData; // data forwarded to `callTarget` to execute swap
    SwapDescriptionV2 desc; // swap desciption
    bytes clientData; // client data
  }
  
  struct Swap {
    bytes data;
    bytes32 selectorAndFlags; // [selector (32 bits) + flags (224 bits)]; selector is 4 most significant bytes; flags are stored in 4 least significant bytes.
  }
  struct SwapExecutorDescription {
    Swap[][] swapSequences;
    address tokenIn;
    address tokenOut;
    address to;
    uint256 deadline;
    bytes positiveSlippageData;
  }

  event Swapped(
    address sender,
    address srcToken,
    address dstToken,
    address dstReceiver,
    uint256 spentAmount,
    uint256 returnAmount
  );

  event ClientData(bytes clientData);

  event Exchange(address pair, uint256 amountOut, address output);

  event Fee(
    address token,
    uint256 totalAmount,
    uint256 totalFee,
    address[] recipients,
    uint256[] amounts,
    bool isBps
  );

  function swapGeneric(SwapExecutionParams memory)
    external
    payable
    returns (uint256 returnAmount, uint256 gasUsed);

  function swap(SwapExecutionParams memory)
    external
    payable
    returns (uint256 returnAmount, uint256 gasUsed);

  function swapSimpleMode(
    address caller,
    SwapDescriptionV2 memory desc,
    bytes calldata executorData,
    bytes calldata clientData
  ) external returns (uint256 returnAmount, uint256 gasUsed);
}
