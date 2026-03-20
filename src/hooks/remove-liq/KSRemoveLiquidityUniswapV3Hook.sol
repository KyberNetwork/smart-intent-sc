// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {BaseTickBasedRemoveLiquidityHook} from '../base/BaseTickBasedRemoveLiquidityHook.sol';

import {IUniswapV3PM} from '../../interfaces/uniswapv3/IUniswapV3PM.sol';
import {IUniswapV3Pool} from '../../interfaces/uniswapv3/IUniswapV3Pool.sol';
import {LiquidityAmounts} from '../../libraries/uniswapv4/LiquidityAmounts.sol';
import {TickMath} from '../../libraries/uniswapv4/TickMath.sol';

import {CalldataDecoder} from 'ks-common-sc/src/libraries/calldata/CalldataDecoder.sol';
import {TokenHelper} from 'ks-common-sc/src/libraries/token/TokenHelper.sol';

import {ActionData} from '../../types/ActionData.sol';
import {IntentData} from '../../types/IntentData.sol';

import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';

contract KSRemoveLiquidityUniswapV3Hook is BaseTickBasedRemoveLiquidityHook {
  using TokenHelper for address;
  using CalldataDecoder for bytes;

  /**
   * @notice Parameters used for remove liquidity validation of a uniswap v3 position
   * @param pool The pool address
   * @param removeLiqParams The params used to remove liquidity
   * @param outputParams The params used to validate output after execution
   */
  struct UniswapV3Params {
    address pool;
    RemoveLiquidityParams removeLiqParams;
    OutputValidationParams outputParams;
  }

  constructor(address _weth) BaseTickBasedRemoveLiquidityHook(_weth) {}

  function _validateBeforeExecution(IntentData calldata intentData, ActionData calldata actionData)
    internal
    view
    override
    returns (bytes memory beforeExecutionData)
  {
    UniswapV3Params memory uniswapV3;
    RemoveLiquidityHookData calldata validationData =
      _decodeHookData(intentData.coreData.hookIntentData);

    _cacheValidationData(uniswapV3, validationData, actionData.hookActionData);

    _validateERC721Data(
      uniswapV3.removeLiqParams.positionInfo.nftAddress,
      uniswapV3.removeLiqParams.positionInfo.nftId,
      intentData.tokenData.erc721Data[actionData.erc721Ids[0]].token,
      intentData.tokenData.erc721Data[actionData.erc721Ids[0]].tokenId
    );

    _validateConditions(
      validationData.nodes[uniswapV3.removeLiqParams.index],
      uniswapV3.removeLiqParams.positionInfo.feesGenerated[0],
      uniswapV3.removeLiqParams.positionInfo.feesGenerated[1],
      uniswapV3.removeLiqParams.sqrtPriceX96
    );

    beforeExecutionData = abi.encode(uniswapV3.removeLiqParams, uniswapV3.outputParams);
  }

  function _getPositionLiquidity(address nftAddress, uint256 nftId)
    internal
    view
    override
    returns (uint256 liquidity)
  {
    (,,,,,,, liquidity,,,,) = IUniswapV3PM(nftAddress).positions(nftId);
  }

  function _cacheValidationData(
    UniswapV3Params memory uniswapV3,
    RemoveLiquidityHookData calldata validationData,
    bytes calldata hookActionData
  ) internal view {
    OutputValidationParams memory outputParams = uniswapV3.outputParams;
    RemoveLiquidityParams memory removeLiqParams = uniswapV3.removeLiqParams;
    _cacheBaseData(validationData, hookActionData, removeLiqParams, outputParams);

    uniswapV3.pool = validationData.additionalData.decodeAddressArray(0)[removeLiqParams.index];
    (
      ,,
      outputParams.tokens[0],
      outputParams.tokens[1],,
      removeLiqParams.positionInfo.ticks[0],
      removeLiqParams.positionInfo.ticks[1],
      removeLiqParams.positionInfo.liquidity,
      removeLiqParams.positionInfo.feesGrowthInsideLast[0],
      removeLiqParams.positionInfo.feesGrowthInsideLast[1],
      removeLiqParams.positionInfo.unclaimedFees[0],
      removeLiqParams.positionInfo.unclaimedFees[1]
    ) =
      IUniswapV3PM(removeLiqParams.positionInfo.nftAddress)
        .positions(removeLiqParams.positionInfo.nftId);

    (removeLiqParams.sqrtPriceX96, removeLiqParams.currentTick,,,,,) =
      IUniswapV3Pool(uniswapV3.pool).slot0();

    if (removeLiqParams.wrapOrUnwrap) {
      outputParams.tokens =
        [_adjustToken(outputParams.tokens[0]), _adjustToken(outputParams.tokens[1])];
    }
    (outputParams.balancesBefore[0], outputParams.balancesBefore[1]) =
      _recordRouterBalances(msg.sender, outputParams.tokens);

    _computePositionValues(uniswapV3);
  }

  function _computePositionValues(UniswapV3Params memory uniswapV3) internal view {
    PositionInfo memory positionInfo = uniswapV3.removeLiqParams.positionInfo;
    RemoveLiquidityParams memory removeLiqParams = uniswapV3.removeLiqParams;

    int24 tickLower = positionInfo.ticks[0];
    int24 tickCurrent = removeLiqParams.currentTick;
    int24 tickUpper = positionInfo.ticks[1];

    if (removeLiqParams.liquidityToRemove != 0) {
      uint160 sqrtPriceLower = TickMath.getSqrtRatioAtTick(tickLower);
      uint160 sqrtPriceUpper = TickMath.getSqrtRatioAtTick(tickUpper);
      (positionInfo.amounts[0], positionInfo.amounts[1]) = LiquidityAmounts.getAmountsForLiquidity(
        removeLiqParams.sqrtPriceX96,
        sqrtPriceLower,
        sqrtPriceUpper,
        uint128(removeLiqParams.liquidityToRemove)
      );
    }

    (uint256 feeGrowthInside0, uint256 feeGrowthInside1) =
      _getFeeGrowthInside(IUniswapV3Pool(uniswapV3.pool), tickLower, tickCurrent, tickUpper);

    unchecked {
      positionInfo.unclaimedFees[
        0
      ] += Math.mulDiv(
        feeGrowthInside0 - positionInfo.feesGrowthInsideLast[0], positionInfo.liquidity, Q128
      );
      positionInfo.unclaimedFees[
        1
      ] += Math.mulDiv(
        feeGrowthInside1 - positionInfo.feesGrowthInsideLast[1], positionInfo.liquidity, Q128
      );
    }
  }

  function _getFeeGrowthInside(
    IUniswapV3Pool pool,
    int24 tickLower,
    int24 tickCurrent,
    int24 tickUpper
  ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
    (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) =
      (pool.feeGrowthGlobal0X128(), pool.feeGrowthGlobal1X128());
    (,, uint256 feeGrowthOutside0X128Lower, uint256 feeGrowthOutside1X128Lower,,,,) =
      pool.ticks(tickLower);
    (,, uint256 feeGrowthOutside0X128Upper, uint256 feeGrowthOutside1X128Upper,,,,) =
      pool.ticks(tickUpper);

    uint256 feeGrowthBelow0X128;
    uint256 feeGrowthBelow1X128;
    unchecked {
      if (tickCurrent >= tickLower) {
        feeGrowthBelow0X128 = feeGrowthOutside0X128Lower;
        feeGrowthBelow1X128 = feeGrowthOutside1X128Lower;
      } else {
        feeGrowthBelow0X128 = feeGrowthGlobal0X128 - feeGrowthOutside0X128Lower;
        feeGrowthBelow1X128 = feeGrowthGlobal1X128 - feeGrowthOutside1X128Lower;
      }

      uint256 feeGrowthAbove0X128;
      uint256 feeGrowthAbove1X128;
      if (tickCurrent < tickUpper) {
        feeGrowthAbove0X128 = feeGrowthOutside0X128Upper;
        feeGrowthAbove1X128 = feeGrowthOutside1X128Upper;
      } else {
        feeGrowthAbove0X128 = feeGrowthGlobal0X128 - feeGrowthOutside0X128Upper;
        feeGrowthAbove1X128 = feeGrowthGlobal1X128 - feeGrowthOutside1X128Upper;
      }

      feeGrowthInside0X128 = feeGrowthGlobal0X128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;
      feeGrowthInside1X128 = feeGrowthGlobal1X128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;
    }
  }
}
