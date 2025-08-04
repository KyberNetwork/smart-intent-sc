// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'src/interfaces/routers/IKSSwapRouter.sol';

import 'ks-common-sc/libraries/token/TokenHelper.sol';
import 'src/validators/base/BaseIntentValidator.sol';

contract KSSwapIntentValidator is BaseIntentValidator {
  using TokenHelper for address;

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

  modifier checkTokenLengths(IKSSessionIntentRouter.TokenData calldata tokenData) override {
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
    checkTokenLengths(actionData.tokenData)
    returns (bytes memory beforeExecutionData)
  {
    uint256 index = abi.decode(actionData.validatorData, (uint256));

    SwapValidationData memory validationData =
      abi.decode(coreData.validationData, (SwapValidationData));

    IKSSessionIntentRouter.ERC20Data[] calldata erc20Data = actionData.tokenData.erc20Data;
    require(erc20Data[0].token == validationData.srcTokens[index], InvalidTokenData());

    uint256 dstBalanceBefore = validationData.dstTokens[index].balanceOf(validationData.recipient);

    return abi.encode(
      validationData.srcTokens[index],
      validationData.dstTokens[index],
      erc20Data[0].amount,
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
      uint256 dstBalanceBefore;
      (srcToken, dstToken, inputAmount, dstBalanceBefore, minRate) =
        abi.decode(beforeExecutionData, (address, address, uint256, uint256, uint256));

      outputAmount = dstToken.balanceOf(validationData.recipient) - dstBalanceBefore;
    }
    if (outputAmount * RATE_DENOMINATOR < inputAmount * minRate) {
      revert BelowMinRate(inputAmount, outputAmount, minRate);
    }
  }
}
