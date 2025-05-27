// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../interfaces/IKSSwapRouter.sol';
import './base/BaseIntentValidator.sol';

import 'openzeppelin-contracts/token/ERC20/IERC20.sol';

contract KSSwapIntentValidator is BaseIntentValidator {
  error InvalidSwapPair();

  error BelowMinRate(uint256 inputAmount, uint256 outputAmount, uint256 minRate);

  uint256 public constant RATE_DENOMINATOR = 1e18;

  /**
   * @notice Data structure for swap validation
   * @param srcTokens The source tokens
   * @param dstTokens The destination tokens
   * @param minRates The minimum rates, denominated in 1e18
   * @param recipient
   */
  struct SwapValidationData {
    address[] srcTokens;
    address[] dstTokens;
    uint256[] minRates;
    address recipient;
  }

  modifier isValidTokenLength(IKSSessionIntentRouter.TokenData calldata tokenData) override {
    require(tokenData.erc20Data.length == 1, InvalidTokenData());
    require(tokenData.erc721Data.length == 0, InvalidTokenData());
    require(tokenData.erc1155Data.length == 0, InvalidTokenData());
    _;
  }

  /// @inheritdoc IKSSessionIntentValidator
  function validateBeforeExecution(
    bytes32,
    IKSSessionIntentRouter.IntentCoreData calldata coreData,
    IKSSessionIntentRouter.ActionData calldata actionData
  )
    external
    view
    override
    isValidTokenLength(actionData.tokenData)
    returns (bytes memory beforeExecutionData)
  {
    uint256 index = abi.decode(actionData.validatorData, (uint256));

    SwapValidationData memory validationData =
      abi.decode(coreData.validationData, (SwapValidationData));

    uint256 srcBalanceBefore = IERC20(validationData.srcTokens[index]).balanceOf(msg.sender);
    uint256 dstBalanceBefore =
      IERC20(validationData.dstTokens[index]).balanceOf(validationData.recipient);

    return abi.encode(
      validationData.srcTokens[index],
      validationData.dstTokens[index],
      srcBalanceBefore,
      dstBalanceBefore,
      validationData.minRates[index]
    );
  }

  /// @inheritdoc IKSSessionIntentValidator
  function validateAfterExecution(
    bytes32,
    IKSSessionIntentRouter.IntentCoreData calldata coreData,
    bytes calldata beforeExecutionData,
    bytes calldata
  ) external view override {
    uint256 minRate;
    uint256 inputAmount;
    uint256 outputAmount;
    SwapValidationData memory validationData =
      abi.decode(coreData.validationData, (SwapValidationData));
    {
      address srcToken;
      address dstToken;
      uint256 srcBalanceBefore;
      uint256 dstBalanceBefore;
      (srcToken, dstToken, srcBalanceBefore, dstBalanceBefore, minRate) =
        abi.decode(beforeExecutionData, (address, address, uint256, uint256, uint256));

      inputAmount = srcBalanceBefore - IERC20(srcToken).balanceOf(msg.sender);
      outputAmount = IERC20(dstToken).balanceOf(validationData.recipient) - dstBalanceBefore;
    }
    if (outputAmount * RATE_DENOMINATOR < inputAmount * minRate) {
      revert BelowMinRate(inputAmount, outputAmount, minRate);
    }
  }
}
