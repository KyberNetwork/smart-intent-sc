// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import '../interfaces/IKSSessionIntentValidator.sol';

contract KSDCAIntentValidator is IKSSessionIntentValidator {
  error ExceedNumSwaps(uint256 numSwaps, uint256 swapNo);
  error InvalidExecutionTime(uint256 startTime, uint256 endTime, uint256 currentTime);
  error InvalidAmountIn(uint256 amountIn, uint256 actualAmountIn);
  error InvalidAmountOut(uint256 minAmountOut, uint256 maxAmountOut, uint256 actualAmountOut);

  /**
   * @notice Data structure for dca validation
   * @param srcToken The source token
   * @param dstToken The destination token
   * @param amountIn The amount of source token to be swapped, should be the same for all swaps
   * @param amountOutLimits The minimum and maximum amount of destination token to be received, should be the same for all swaps (minAmountOut 128bits, maxAmountOut 128bits)
   * @param executionParams The parameters for swaps validation (numSwaps 32bits, duration 32bits, startPeriod 32bits, firstTimestamp 32bits)
   */
  struct DCAValidationData {
    address srcToken;
    address dstToken;
    uint256 amountIn;
    uint256 amountOutLimits;
    uint256 executionParams;
  }

  /// @inheritdoc IKSSessionIntentValidator
  function validateBeforeExecution(
    IKSSessionIntentRouter.IntentCoreData calldata coreData,
    IKSSessionIntentRouter.ActionData calldata actionData
  ) external view override returns (bytes memory beforeExecutionData) {
    DCAValidationData memory validationData =
      abi.decode(coreData.validationData, (DCAValidationData));

    uint256 swapNo = abi.decode(actionData.validatorData, (uint256));
    uint32 numSwaps = uint32(validationData.executionParams >> 96);

    if (swapNo >= numSwaps) {
      revert ExceedNumSwaps(numSwaps, swapNo);
    }

    //validate execution time
    if (uint96(validationData.executionParams) != 0) {
      uint32 duration = uint32(validationData.executionParams >> 64);
      uint32 startPeriod = uint32(validationData.executionParams >> 32);
      uint32 firstTimestamp = uint32(validationData.executionParams);

      uint256 startTime = firstTimestamp + duration * swapNo;
      uint256 endTime = startTime + startPeriod;

      if (block.timestamp < startTime || endTime < block.timestamp) {
        revert InvalidExecutionTime(startTime, endTime, uint32(block.timestamp));
      }
    }

    //validate amountIn, currently only support 1 tokenIn
    if (
      actionData.tokenData.erc20Data.length != 1
        || actionData.tokenData.erc20Data[0].amount != validationData.amountIn
    ) {
      revert InvalidAmountIn(validationData.amountIn, actionData.tokenData.erc20Data[0].amount);
    }

    return abi.encode(validationData.amountOutLimits);
  }

  /// @inheritdoc IKSSessionIntentValidator
  function validateAfterExecution(
    IKSSessionIntentRouter.IntentCoreData calldata,
    bytes calldata beforeExecutionData,
    bytes calldata actionResult
  ) external pure override {
    uint256 amountOutLimits = abi.decode(beforeExecutionData, (uint256));
    (uint256 amountOut,) = abi.decode(actionResult, (uint256, uint256));

    uint128 minAmountOut = uint128(amountOutLimits >> 128);
    uint128 maxAmountOut = uint128(amountOutLimits);

    if (amountOut < minAmountOut || maxAmountOut < amountOut) {
      revert InvalidAmountOut(minAmountOut, maxAmountOut, amountOut);
    }
  }
}
