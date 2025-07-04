// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../libraries/TokenLibrary.sol';
import './base/BaseIntentValidator.sol';

import 'openzeppelin-contracts/token/ERC20/IERC20.sol';

import 'src/interfaces/uniswapv3/IUniswapV3PM.sol';
import 'src/interfaces/uniswapv3/IUniswapV3Pool.sol';

contract KSZapOutUniswapV3IntentValidator is BaseIntentValidator {
  using TokenLibrary for address;

  error InvalidZapOutPosition();

  error OutsidePriceRange(uint160 sqrtPLower, uint160 sqrtPUpper, uint160 sqrtPriceX96);

  error InvalidOwner();

  error GetPositionLiquidityFailed();

  error GetSqrtPriceX96Failed();

  error BelowMinRate(uint256 liquidity, uint256 minRate, uint256 outputAmount);

  uint256 public constant RATE_DENOMINATOR = 1e18;

  struct ZapOutUniswapV3ValidationData {
    address[] nftAddresses;
    uint256[] nftIds;
    address[] pools;
    address[] outputTokens;
    uint256[] offsets;
    uint160[] sqrtPLowers;
    uint160[] sqrtPUppers;
    uint256[] minRates;
    address recipient;
  }

  modifier checkTokenLengths(IKSSessionIntentRouter.TokenData calldata tokenData) override {
    require(tokenData.erc20Data.length == 0, InvalidTokenData());
    require(tokenData.erc721Data.length == 1, InvalidTokenData());
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

    ZapOutUniswapV3ValidationData memory validationData =
      abi.decode(coreData.validationData, (ZapOutUniswapV3ValidationData));

    IKSSessionIntentRouter.ERC721Data[] calldata erc721Data = actionData.tokenData.erc721Data;
    require(erc721Data[0].token == validationData.nftAddresses[index], InvalidTokenData());
    require(erc721Data[0].tokenId == validationData.nftIds[index], InvalidTokenData());

    uint160 sqrtPriceX96 =
      _getSqrtPriceX96(validationData.pools[index], validationData.offsets[index] >> 128);
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
      uint128(validationData.offsets[index])
    );
    uint256 tokenBalanceBefore =
      validationData.outputTokens[index].balanceOf(validationData.recipient);

    return abi.encode(
      validationData.nftAddresses[index],
      validationData.nftIds[index],
      validationData.outputTokens[index],
      liquidityBefore,
      tokenBalanceBefore,
      uint128(validationData.offsets[index]),
      validationData.minRates[index],
      validationData.recipient
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

    {
      address nftAddress;
      uint256 nftId;
      address outputToken;
      uint256 liquidityBefore;
      uint256 tokenBalanceBefore;
      uint256 liquidityOffset;
      address recipient;

      (
        nftAddress,
        nftId,
        outputToken,
        liquidityBefore,
        tokenBalanceBefore,
        liquidityOffset,
        minRate,
        recipient
      ) = abi.decode(
        beforeExecutionData,
        (address, uint256, address, uint256, uint256, uint256, uint256, address)
      );

      uint256 liquidityAfter = _getPositionLiquidity(nftAddress, nftId, liquidityOffset);
      require(
        liquidityAfter == 0 || IERC721(nftAddress).ownerOf(nftId) == coreData.mainAddress,
        InvalidOwner()
      );
      liquidity = liquidityBefore - liquidityAfter;

      outputAmount = outputToken.balanceOf(recipient) - tokenBalanceBefore;
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

  function _getSqrtPriceX96(address pool, uint256 priceOffset)
    internal
    view
    returns (uint160 sqrtPriceX96)
  {
    (bool success, bytes memory result) =
      address(pool).staticcall(abi.encodeWithSelector(IUniswapV3Pool.slot0.selector));
    require(success, GetSqrtPriceX96Failed());
    assembly {
      sqrtPriceX96 := mload(add(result, priceOffset))
    }
  }
}
