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
    (address nftAddress, uint256 nftId, address outputToken) =
      abi.decode(actionData.validatorData, (address, uint256, address));

    address pool;
    uint256 liquidityOffset;
    uint256 minRate;
    uint160 sqrtPLower;
    uint160 sqrtPUpper;
    ZapOutUniswapV3ValidationData memory validationData =
      abi.decode(coreData.validationData, (ZapOutUniswapV3ValidationData));

    for (uint256 i = 0; i < validationData.nftAddresses.length; i++) {
      if (
        validationData.nftAddresses[i] == nftAddress && validationData.nftIds[i] == nftId
          && validationData.outputTokens[i] == outputToken
      ) {
        pool = validationData.pools[i];
        liquidityOffset = 0x20 + 0x20 * validationData.liquidityOffsets[i];
        sqrtPLower = validationData.sqrtPLowers[i];
        sqrtPUpper = validationData.sqrtPUppers[i];
        minRate = validationData.minRates[i];

        break;
      }
    }

    if (pool == address(0)) {
      revert InvalidZapOutPosition();
    }
    (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
    require(
      sqrtPriceX96 >= sqrtPLower && sqrtPriceX96 <= sqrtPUpper,
      OutsidePriceRange(sqrtPLower, sqrtPUpper, sqrtPriceX96)
    );

    uint256 liquidityBefore = _getPositionLiquidity(nftAddress, nftId, liquidityOffset);
    uint256 tokenBalanceBefore = outputToken == ETH_ADDRESS
      ? validationData.recipient.balance
      : IERC20(outputToken).balanceOf(validationData.recipient);

    return abi.encode(
      nftAddress, nftId, outputToken, liquidityBefore, tokenBalanceBefore, liquidityOffset, minRate
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
