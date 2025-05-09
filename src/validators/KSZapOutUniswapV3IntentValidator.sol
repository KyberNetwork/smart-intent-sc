// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../interfaces/IKSSessionIntentValidator.sol';
import 'openzeppelin-contracts/token/ERC20/IERC20.sol';
import 'src/interfaces/uniswapv3/IUniswapV3PM.sol';
import 'src/interfaces/uniswapv3/IUniswapV3Pool.sol';

contract KSZapOutUniswapV3IntentValidator is IKSSessionIntentValidator {
  error InvalidZapOutPosition();

  error OutsidePriceRange(uint160 sqrtPLower, uint160 sqrtPUpper, uint160 sqrtPriceX96);

  error GetPositionLiquidityFailed();

  error BelowMinRate(uint256 liquidity, uint256 minRate, uint256 outputAmount);

  uint256 public constant RATE_DENOMINATOR = 1e18;

  address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  struct ZapOutUniswapV3ValidationData {
    address[] nftAddresses;
    uint256[] nftIds;
    address[] pools;
    address[] outputTokens;
    uint256[] liquidityOffsets;
    uint160[] sqrtPLowers;
    uint160[] sqrtPUppers;
    uint256[] minRates;
    address recipient;
  }

  /// @inheritdoc IKSSessionIntentValidator
  function validateBeforeExecution(
    bytes32,
    IKSSessionIntentRouter.IntentCoreData calldata coreData,
    IKSSessionIntentRouter.ActionData calldata actionData
  ) external view override returns (bytes memory beforeExecutionData) {
    uint256 index = abi.decode(actionData.validatorData, (uint256));

    ZapOutUniswapV3ValidationData memory validationData =
      abi.decode(coreData.validationData, (ZapOutUniswapV3ValidationData));

    (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(validationData.pools[index]).slot0();
    require(
      sqrtPriceX96 >= validationData.sqrtPLowers[index]
        && sqrtPriceX96 <= validationData.sqrtPUppers[index],
      OutsidePriceRange(
        validationData.sqrtPLowers[index], validationData.sqrtPUppers[index], sqrtPriceX96
      )
    );

    uint256 liquidityBefore = _getPositionLiquidity(
      validationData.nftAddresses[index],
      validationData.nftIds[index],
      validationData.liquidityOffsets[index]
    );
    uint256 tokenBalanceBefore = validationData.outputTokens[index] == ETH_ADDRESS
      ? validationData.recipient.balance
      : IERC20(validationData.outputTokens[index]).balanceOf(validationData.recipient);

    return abi.encode(
      validationData.nftAddresses[index],
      validationData.nftIds[index],
      validationData.outputTokens[index],
      liquidityBefore,
      tokenBalanceBefore,
      validationData.liquidityOffsets[index],
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
    uint256 liquidity;
    uint256 outputAmount;
    ZapOutUniswapV3ValidationData memory validationData =
      abi.decode(coreData.validationData, (ZapOutUniswapV3ValidationData));

    {
      address nftAddress;
      uint256 nftId;
      address outputToken;
      uint256 liquidityBefore;
      uint256 tokenBalanceBefore;
      uint256 liquidityOffset;

      (
        nftAddress,
        nftId,
        outputToken,
        liquidityBefore,
        tokenBalanceBefore,
        liquidityOffset,
        minRate
      ) = abi.decode(
        beforeExecutionData, (address, uint256, address, uint256, uint256, uint256, uint256)
      );

      uint256 liquidityAfter = _getPositionLiquidity(nftAddress, nftId, liquidityOffset);
      liquidity = liquidityBefore - liquidityAfter;

      outputAmount = outputToken == ETH_ADDRESS
        ? validationData.recipient.balance - tokenBalanceBefore
        : IERC20(outputToken).balanceOf(validationData.recipient);
      outputAmount -= tokenBalanceBefore;
    }

    if (outputAmount * RATE_DENOMINATOR < minRate * liquidity) {
      revert BelowMinRate(liquidity, minRate, outputAmount);
    }
  }

  function _getPositionLiquidity(address nftAddress, uint256 nftId, uint256 liquidityOffset)
    internal
    view
    returns (uint256 liquidity)
  {
    (bool success, bytes memory result) =
      address(nftAddress).staticcall(abi.encodeWithSelector(IUniswapV3PM.positions.selector, nftId));
    require(success, GetPositionLiquidityFailed());
    assembly {
      liquidity := mload(add(result, liquidityOffset))
    }
  }
}
