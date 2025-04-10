// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../interfaces/IKSSessionIntentValidator.sol';
import 'openzeppelin-contracts/token/ERC20/IERC20.sol';
import 'src/interfaces/uniswapv3/IUniswapV3PM.sol';

contract KSZapOutUniswapV3IntentValidator is IKSSessionIntentValidator {
  error InvalidZapOutPosition();

  error BelowMinRate(uint128 liquidity, uint256 outputAmount, uint256 minRate);

  uint256 public constant RATE_DENOMINATOR = 1e18;

  struct ZapOutUniswapV3ValidationData {
    address[] nftAddresses;
    uint256[] nftIds;
    address[] outputTokens;
    uint256[] minRates;
    address recipient;
  }

  /// @inheritdoc IKSSessionIntentValidator
  function validateBeforeExecution(
    bytes32,
    IKSSessionIntentRouter.IntentCoreData calldata coreData,
    IKSSessionIntentRouter.ActionData calldata actionData
  ) external view override returns (bytes memory beforeExecutionData) {
    (address nftAddress, uint256 nftId, address outputToken) =
      abi.decode(actionData.validatorData, (address, uint256, address));

    uint256 minRate;
    ZapOutUniswapV3ValidationData memory validationData =
      abi.decode(coreData.validationData, (ZapOutUniswapV3ValidationData));
    for (uint256 i = 0; i < validationData.nftAddresses.length; i++) {
      if (
        validationData.nftAddresses[i] == nftAddress && validationData.nftIds[i] == nftId
          && validationData.outputTokens[i] == outputToken
      ) {
        minRate = validationData.minRates[i];
        break;
      }
    }
    if (minRate == 0) {
      revert InvalidZapOutPosition();
    }

    (,,,,,,, uint128 liquidityBefore,,,,) = IUniswapV3PM(nftAddress).positions(nftId);
    uint256 tokenBalanceBefore = IERC20(outputToken).balanceOf(validationData.recipient);

    return abi.encode(nftAddress, nftId, outputToken, liquidityBefore, tokenBalanceBefore, minRate);
  }

  /// @inheritdoc IKSSessionIntentValidator
  function validateAfterExecution(
    bytes32,
    IKSSessionIntentRouter.IntentCoreData calldata coreData,
    bytes calldata beforeExecutionData,
    bytes calldata
  ) external view override {
    uint256 minRate;
    uint128 liquidity;
    uint256 outputAmount;
    ZapOutUniswapV3ValidationData memory validationData =
      abi.decode(coreData.validationData, (ZapOutUniswapV3ValidationData));
    {
      address nftAddress;
      uint256 nftId;
      address outputToken;
      uint128 liquidityBefore;
      uint256 tokenBalanceBefore;
      (nftAddress, nftId, outputToken, liquidityBefore, tokenBalanceBefore, minRate) =
        abi.decode(beforeExecutionData, (address, uint256, address, uint128, uint256, uint256));
      uint128 liquidityAfter;
      (,,,,,,, liquidityAfter,,,,) = IUniswapV3PM(nftAddress).positions(nftId);
      liquidity = liquidityBefore - liquidityAfter;
      outputAmount = IERC20(outputToken).balanceOf(validationData.recipient) - tokenBalanceBefore;
    }
    if (outputAmount * RATE_DENOMINATOR < minRate * liquidity) {
      revert BelowMinRate(liquidity, outputAmount, minRate);
    }
  }
}
