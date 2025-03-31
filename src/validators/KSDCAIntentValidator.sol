// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../interfaces/IKSSessionIntentValidator.sol';
import '../interfaces/IKSSwapRouter.sol';

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract KSDCAIntentValidator is IKSSessionIntentValidator {
  error InvalidActionSelector();
  error InvalidExecutionTime(uint32 executionTime, uint32 currentTime);
  error AboveInputAmount(uint256 inputAmount, uint256 actualAmount);
  error BelowOutputAmount(uint256 outputAmount, uint256 actualAmount);

  uint256 public constant TIME_THRESHOLD = 60;

  /**
   * @notice Data structure for dca validation
   * @param srcToken The source token
   * @param dstToken The destination token
   * @param amountIn The amount of source token
   * @param executionTime timestamp for execution
   * @param minAmountOut The minimum amount of destination token to be received
   */
  struct DCAValidationData {
    address srcToken;
    address dstToken;
    uint256 amountIn;
    uint256 minAmountOut;
    uint32 executionTime;
  }

  /// @inheritdoc IKSSessionIntentValidator
  function validateBeforeExecution(
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

    DCAValidationData memory validationData =
      abi.decode(coreData.validationData, (DCAValidationData));

    if (validationData.executionTime != 0) {
      // ignore timestamp on price-based DCA
      if (
        block.timestamp < validationData.executionTime - TIME_THRESHOLD
          || validationData.executionTime + TIME_THRESHOLD < block.timestamp
      ) {
        revert InvalidExecutionTime(validationData.executionTime, uint32(block.timestamp));
      }
    }

    uint256 srcBalanceBefore = IERC20(swapDesc.srcToken).balanceOf(coreData.mainWallet);
    uint256 dstBalanceBefore = IERC20(swapDesc.dstToken).balanceOf(swapDesc.dstReceiver);

    return abi.encode(
      swapDesc.srcToken,
      swapDesc.dstToken,
      srcBalanceBefore,
      dstBalanceBefore,
      validationData.amountIn,
      validationData.minAmountOut,
      swapDesc.dstReceiver
    );
  }

  /// @inheritdoc IKSSessionIntentValidator
  function validateAfterExecution(
    IKSSessionIntentRouter.IntentCoreData calldata coreData,
    bytes calldata beforeExecutionData,
    bytes calldata actionResult
  ) external view override {
    (
      address srcToken,
      address dstToken,
      uint256 srcBalanceBefore,
      uint256 dstBalanceBefore,
      uint256 inputAmount,
      uint256 outputAmount,
      address dstReceiver
    ) = abi.decode(
      beforeExecutionData, (address, address, uint256, uint256, uint256, uint256, address)
    );

    {
      uint256 actualInputAmount = srcBalanceBefore - IERC20(srcToken).balanceOf(coreData.mainWallet);

      if (actualInputAmount > inputAmount) {
        revert AboveInputAmount(inputAmount, actualInputAmount);
      }
    }

    {
      uint256 actualOutputAmount = IERC20(dstToken).balanceOf(dstReceiver) - dstBalanceBefore;
      if (actualOutputAmount < outputAmount) {
        revert BelowOutputAmount(outputAmount, actualOutputAmount);
      }
    }
  }
}
