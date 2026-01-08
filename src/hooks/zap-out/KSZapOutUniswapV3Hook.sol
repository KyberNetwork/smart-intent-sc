// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IKSSmartIntentHook} from '../../interfaces/hooks/IKSSmartIntentHook.sol';
import {BaseHook} from '../base/BaseHook.sol';

import {ActionData} from '../../types/ActionData.sol';
import {ERC721Data} from '../../types/ERC721Data.sol';
import {IntentData} from '../../types/IntentData.sol';

import {IUniswapV3PM} from '../../interfaces/uniswapv3/IUniswapV3PM.sol';
import {IUniswapV3Pool} from '../../interfaces/uniswapv3/IUniswapV3Pool.sol';

import {TokenHelper} from 'ks-common-sc/src/libraries/token/TokenHelper.sol';

import {IERC721} from 'openzeppelin-contracts/contracts/interfaces/IERC721.sol';

contract KSZapOutUniswapV3Hook is BaseHook {
  using TokenHelper for address;

  error InvalidZapOutPosition();

  error OutsidePriceRange(uint160 sqrtPLower, uint160 sqrtPUpper, uint160 sqrtPriceX96);

  error InvalidOwner();

  error GetPositionLiquidityFailed();

  error GetSqrtPriceX96Failed();

  error BelowMinRate(uint256 liquidity, uint256 minRate, uint256 outputAmount);

  uint256 public constant RATE_DENOMINATOR = 1e18;

  struct ZapOutUniswapV3HookData {
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

  modifier checkTokenLengths(ActionData calldata actionData) override {
    require(actionData.erc20Ids.length == 0, InvalidTokenData());
    require(actionData.erc721Ids.length == 1, InvalidTokenData());
    _;
  }

  /// @inheritdoc IKSSmartIntentHook
  function beforeExecution(bytes32, IntentData calldata intentData, ActionData calldata actionData)
    external
    view
    override
    checkTokenLengths(actionData)
    returns (uint256[] memory fees, bytes memory beforeExecutionData)
  {
    uint256 index = abi.decode(actionData.hookActionData, (uint256));

    ZapOutUniswapV3HookData memory zapOutHookData =
      abi.decode(intentData.coreData.hookIntentData, (ZapOutUniswapV3HookData));

    ERC721Data calldata erc721Data = intentData.tokenData.erc721Data[actionData.erc721Ids[0]];
    require(erc721Data.token == zapOutHookData.nftAddresses[index], InvalidTokenData());
    require(erc721Data.tokenId == zapOutHookData.nftIds[index], InvalidTokenData());

    uint160 sqrtPriceX96 =
      _getSqrtPriceX96(zapOutHookData.pools[index], zapOutHookData.offsets[index] >> 128);
    require(
      sqrtPriceX96 >= zapOutHookData.sqrtPLowers[index]
        && sqrtPriceX96 <= zapOutHookData.sqrtPUppers[index],
      OutsidePriceRange(
        zapOutHookData.sqrtPLowers[index], zapOutHookData.sqrtPUppers[index], sqrtPriceX96
      )
    );

    uint256 liquidityBefore = _getPositionLiquidity(
      zapOutHookData.nftAddresses[index],
      zapOutHookData.nftIds[index],
      uint128(zapOutHookData.offsets[index])
    );
    uint256 tokenBalanceBefore =
      zapOutHookData.outputTokens[index].balanceOf(zapOutHookData.recipient);

    fees = new uint256[](actionData.erc20Ids.length);
    beforeExecutionData = abi.encode(
      zapOutHookData.nftAddresses[index],
      zapOutHookData.nftIds[index],
      zapOutHookData.outputTokens[index],
      liquidityBefore,
      tokenBalanceBefore,
      uint128(zapOutHookData.offsets[index]),
      zapOutHookData.minRates[index],
      zapOutHookData.recipient
    );
  }

  /// @inheritdoc IKSSmartIntentHook
  function afterExecution(
    bytes32,
    IntentData calldata intentData,
    bytes calldata beforeExecutionData,
    bytes calldata
  ) external view override returns (address[] memory, uint256[] memory, uint256[] memory, address) {
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
      ) =
        abi.decode(
          beforeExecutionData,
          (address, uint256, address, uint256, uint256, uint256, uint256, address)
        );

      uint256 liquidityAfter = _getPositionLiquidity(nftAddress, nftId, liquidityOffset);
      require(
        liquidityAfter == 0
          || IERC721(nftAddress).ownerOf(nftId) == intentData.coreData.mainAddress,
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
