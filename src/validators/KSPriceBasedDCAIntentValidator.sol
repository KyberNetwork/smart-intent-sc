// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'openzeppelin-contracts/token/ERC20/IERC20.sol';

import './base/BaseStatefulIntentValidator.sol';

contract KSPriceBasedDCAIntentValidator is BaseStatefulIntentValidator {
  error ExceedNumSwaps(uint256 numSwaps, uint256 swapNo);
  error InvalidTokenIn(address tokenIn, address actualTokenIn);
  error InvalidAmountIn(uint256 amountIn, uint256 actualAmountIn);
  error InvalidAmountOut(uint256 minAmountOut, uint256 maxAmountOut, uint256 actualAmountOut);
  error SwapAlreadyExecuted();

  /**
   * @notice Data structure for dca validation
   * @param srcToken The source token
   * @param dstToken The destination token
   * @param amountIns
   * @param amountOutLimits
   */
  struct DCAValidationData {
    address srcToken;
    address dstToken;
    uint256[] amountIns;
    uint256[] amountOutLimits;
  }

  address private constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

  mapping(bytes32 => uint256) public latestSwap;

  constructor(address[] memory initialRouters) BaseStatefulIntentValidator(initialRouters) {}

  /// @inheritdoc IKSSessionIntentValidator
  function validateBeforeExecution(
    bytes32 intentHash,
    IKSSessionIntentRouter.IntentCoreData calldata coreData,
    IKSSessionIntentRouter.ActionData calldata actionData
  ) external override onlyWhitelistedRouter returns (bytes memory beforeExecutionData) {
    DCAValidationData memory validationData =
      abi.decode(coreData.validationData, (DCAValidationData));

    uint256 swapNo = abi.decode(actionData.validatorData, (uint256));
    uint256 numSwaps = validationData.amountOutLimits.length;

    if (swapNo >= numSwaps) {
      revert ExceedNumSwaps(numSwaps, swapNo);
    }

    //validate amountIn, currently only support 1 tokenIn
    if (
      actionData.tokenData.erc20Data.length != 1
        || actionData.tokenData.erc20Data[0].token != validationData.srcToken
    ) {
      revert InvalidTokenIn(validationData.srcToken, actionData.tokenData.erc20Data[0].token);
    }

    if (actionData.tokenData.erc20Data[0].amount != validationData.amountIns[swapNo]) {
      revert InvalidAmountIn(
        validationData.amountIns[swapNo], actionData.tokenData.erc20Data[0].amount
      );
    }

    //validate this swap is not executed before
    swapNo++; //swapNo starts from 0, latestSwap starts from 1
    if (swapNo <= latestSwap[intentHash]) {
      revert SwapAlreadyExecuted();
    }
    latestSwap[intentHash] = swapNo;

    uint256 balanceBefore;
    if (validationData.dstToken == ETH_ADDRESS) {
      balanceBefore = coreData.recipient.balance;
    } else {
      balanceBefore = IERC20(validationData.dstToken).balanceOf(coreData.recipient);
    }

    return abi.encode(--swapNo, balanceBefore);
  }

  /// @inheritdoc IKSSessionIntentValidator
  function validateAfterExecution(
    bytes32,
    IKSSessionIntentRouter.IntentCoreData calldata coreData,
    bytes calldata beforeExecutionData,
    bytes calldata
  ) external view override onlyWhitelistedRouter {
    DCAValidationData memory validationData =
      abi.decode(coreData.validationData, (DCAValidationData));

    (uint256 swapNo, uint256 balanceBefore) = abi.decode(beforeExecutionData, (uint256, uint256));

    uint128 minAmountOut = uint128(validationData.amountOutLimits[swapNo] >> 128);
    uint128 maxAmountOut = uint128(validationData.amountOutLimits[swapNo]);

    uint256 amountOut;
    if (validationData.dstToken == ETH_ADDRESS) {
      amountOut = coreData.recipient.balance - balanceBefore;
    } else {
      amountOut = IERC20(validationData.dstToken).balanceOf(coreData.recipient) - balanceBefore;
    }

    if (amountOut < minAmountOut || maxAmountOut < amountOut) {
      revert InvalidAmountOut(minAmountOut, maxAmountOut, amountOut);
    }
  }
}
