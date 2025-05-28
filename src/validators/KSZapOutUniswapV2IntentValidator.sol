// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../interfaces/IKSSessionIntentValidator.sol';
import '../interfaces/IKSSwapRouter.sol';
import '../interfaces/uniswapv2/IUniswapV2Pair.sol';

import 'openzeppelin-contracts/token/ERC20/IERC20.sol';

contract KSZapOutUniswapV2IntentValidator is IKSSessionIntentValidator {
  error InvalidSwapPair();

  error BelowMinRate(uint256 inputAmount, uint256 outputAmount, uint256 minRate);

  error OutsidePriceRange(uint256 priceLower, uint256 priceUpper, uint256 priceCurrent);

  uint256 public constant RATE_DENOMINATOR = 1e18;

  /**
   * @notice Data structure for swap validation
   * @param srcTokens The source tokens
   * @param dstTokens The destination tokens
   * @param priceLowers The lower price bounds, denominated in 1e18
   * @param priceUppers The upper price bounds, denominated in 1e18
   * @param minRates The minimum rates, denominated in 1e18
   * @param recipient
   */
  struct ZapOutUniswapV2ValidationData {
    address[] srcTokens;
    address[] dstTokens;
    uint256[] priceLowers;
    uint256[] priceUppers;
    uint256[] minRates;
    address recipient;
  }

  /// @inheritdoc IKSSessionIntentValidator
  function validateBeforeExecution(
    bytes32,
    IKSSessionIntentRouter.IntentCoreData calldata coreData,
    IKSSessionIntentRouter.ActionData calldata actionData
  ) external override returns (bytes memory beforeExecutionData) {
    uint256 index = abi.decode(actionData.validatorData, (uint256));

    ZapOutUniswapV2ValidationData memory validationData =
      abi.decode(coreData.validationData, (ZapOutUniswapV2ValidationData));

    uint256 srcBalanceBefore = IERC20(validationData.srcTokens[index]).balanceOf(msg.sender);
    uint256 dstBalanceBefore =
      IERC20(validationData.dstTokens[index]).balanceOf(validationData.recipient);

    // this will works for most of UniswapV2 forks
    // as they have different ways to get the reserves
    IUniswapV2Pair(validationData.srcTokens[index]).skim(validationData.recipient);
    uint256 priceCurrent;
    {
      address token0 = IUniswapV2Pair(validationData.srcTokens[index]).token0();
      address token1 = IUniswapV2Pair(validationData.srcTokens[index]).token1();
      uint256 reserve0 = IERC20(token0).balanceOf(validationData.srcTokens[index]);
      uint256 reserve1 = IERC20(token1).balanceOf(validationData.srcTokens[index]);
      priceCurrent = (reserve1 * RATE_DENOMINATOR) / reserve0;
    }
    require(
      priceCurrent >= validationData.priceLowers[index]
        && priceCurrent <= validationData.priceUppers[index],
      OutsidePriceRange(
        validationData.priceLowers[index], validationData.priceUppers[index], priceCurrent
      )
    );

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
    ZapOutUniswapV2ValidationData memory validationData =
      abi.decode(coreData.validationData, (ZapOutUniswapV2ValidationData));
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
