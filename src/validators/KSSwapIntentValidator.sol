// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../interfaces/IKSSessionIntentValidator.sol';
import '../interfaces/IKSSwapRouter.sol';

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract KSSwapIntentValidator is IKSSessionIntentValidator {
  error InvalidActionSelector();

  error InvalidSwapPair();

  error BelowMinRate(uint256 inputAmount, uint256 outputAmount, uint256 minRate);

  uint256 public constant RATE_DENOMINATOR = 1e18;

  /**
   * @notice Data structure for swap validation
   * @param srcTokens The source tokens
   * @param dstTokens The destination tokens
   * @param minRates The minimum rates, denominated in 1e18
   */
  struct SwapValidationData {
    address[] srcTokens;
    address[] dstTokens;
    uint256[] minRates;
  }

  /// @inheritdoc IKSSessionIntentValidator
  function validateBeforeExecution(
    bytes32,
    IKSSessionIntentRouter.IntentCoreData calldata coreData,
    IKSSessionIntentRouter.ActionData calldata actionData
  ) external view override returns (bytes memory beforeExecutionData) {
    IKSSwapRouter.SwapDescriptionV2 memory swapDesc;
    if (coreData.actionSelector == IKSSwapRouter.swap.selector) {
      IKSSwapRouter.SwapExecutionParams memory params =
        abi.decode(actionData.actionCalldata, (IKSSwapRouter.SwapExecutionParams));
      swapDesc = params.desc;
    } else if (coreData.actionSelector == IKSSwapRouter.swapSimpleMode.selector) {
      (, swapDesc,,) = abi.decode(
        actionData.actionCalldata, (address, IKSSwapRouter.SwapDescriptionV2, bytes, bytes)
      );
    } else {
      revert InvalidActionSelector();
    }

    uint256 minRate;
    SwapValidationData memory validationData =
      abi.decode(coreData.validationData, (SwapValidationData));
    for (uint256 i = 0; i < validationData.srcTokens.length; i++) {
      if (
        validationData.srcTokens[i] == swapDesc.srcToken
          && validationData.dstTokens[i] == swapDesc.dstToken
      ) {
        minRate = validationData.minRates[i];
        break;
      }
    }
    if (minRate == 0) {
      revert InvalidSwapPair();
    }

    uint256 srcBalanceBefore = IERC20(swapDesc.srcToken).balanceOf(address(this));

    return abi.encode(swapDesc.srcToken, swapDesc.dstToken, srcBalanceBefore, minRate);
  }

  /// @inheritdoc IKSSessionIntentValidator
  function validateAfterExecution(
    bytes32,
    IKSSessionIntentRouter.IntentCoreData calldata,
    bytes calldata beforeExecutionData,
    bytes calldata actionResult
  ) external view override {
    uint256 minRate;
    uint256 inputAmount;
    {
      address srcToken;
      uint256 srcBalanceBefore;
      (srcToken,, srcBalanceBefore, minRate) =
        abi.decode(beforeExecutionData, (address, address, uint256, uint256));
      uint256 srcBalanceAfter = IERC20(srcToken).balanceOf(address(this));
      inputAmount = srcBalanceBefore - srcBalanceAfter;
    }
    (uint256 outputAmount,) = abi.decode(actionResult, (uint256, uint256));
    if (outputAmount * RATE_DENOMINATOR < inputAmount * minRate) {
      revert BelowMinRate(inputAmount, outputAmount, minRate);
    }
  }
}
