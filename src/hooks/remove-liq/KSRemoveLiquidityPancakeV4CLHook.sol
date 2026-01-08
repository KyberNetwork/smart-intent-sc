// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {TokenHelper} from 'ks-common-sc/src/libraries/token/TokenHelper.sol';

import {ICLPoolManager} from '../../interfaces/pancakev4/ICLPoolManager.sol';
import {ICLPositionManager} from '../../interfaces/pancakev4/ICLPositionManager.sol';
import {PoolId, PoolKey, TickInfo} from '../../interfaces/pancakev4/Types.sol';
import {LiquidityAmounts} from '../../libraries/uniswapv4/LiquidityAmounts.sol';
import {TickMath} from '../../libraries/uniswapv4/TickMath.sol';
import {BaseTickBasedRemoveLiquidityHook} from '../base/BaseTickBasedRemoveLiquidityHook.sol';

import {ActionData} from '../../types/ActionData.sol';
import {IntentData} from '../../types/IntentData.sol';

import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';

contract KSRemoveLiquidityPancakeV4CLHook is BaseTickBasedRemoveLiquidityHook {
  using TokenHelper for address;

  /**
   * @notice Parameters used for remove liquidity validation of a pancake v4 CL position
   * @param clPoolManager The cl pool manager contract
   * @param poolId The pool ID
   * @param removeLiqParams The params used to remove liquidity
   * @param outputParams The params used to validate output after execution
   */
  struct PancakeV4CLParams {
    ICLPoolManager clPoolManager;
    PoolId poolId;
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
    PancakeV4CLParams memory pancakeCL;

    RemoveLiquidityHookData calldata validationData =
      _decodeHookData(intentData.coreData.hookIntentData);

    _cacheValidationData(pancakeCL, validationData, actionData.hookActionData);

    _validateConditions(
      validationData.nodes[pancakeCL.removeLiqParams.index],
      pancakeCL.removeLiqParams.positionInfo.feesGenerated[0],
      pancakeCL.removeLiqParams.positionInfo.feesGenerated[1],
      pancakeCL.removeLiqParams.sqrtPriceX96
    );

    beforeExecutionData = abi.encode(pancakeCL.removeLiqParams, pancakeCL.outputParams);
  }

  function _cacheValidationData(
    PancakeV4CLParams memory pancakeCL,
    RemoveLiquidityHookData calldata validationData,
    bytes calldata hookActionData
  ) internal view {
    OutputValidationParams memory outputParams = pancakeCL.outputParams;
    RemoveLiquidityParams memory removeLiqParams = pancakeCL.removeLiqParams;

    _cacheBaseData(validationData, hookActionData, removeLiqParams, outputParams);

    ICLPositionManager positionManager = ICLPositionManager(removeLiqParams.positionInfo.nftAddress);
    PoolKey memory poolKey;
    (
      poolKey,
      removeLiqParams.positionInfo.ticks[0],
      removeLiqParams.positionInfo.ticks[1],
      removeLiqParams.positionInfo.liquidity,
      removeLiqParams.positionInfo.feesGrowthInsideLast[0],
      removeLiqParams.positionInfo.feesGrowthInsideLast[1],
    ) = positionManager.positions(removeLiqParams.positionInfo.nftId);
    pancakeCL.poolId = _toId(poolKey);

    (removeLiqParams.sqrtPriceX96, removeLiqParams.currentTick,,) =
      (pancakeCL.clPoolManager = positionManager.clPoolManager()).getSlot0(pancakeCL.poolId);
    outputParams.tokens = [_toNative(poolKey.currency0), _toNative(poolKey.currency1)];

    if (removeLiqParams.wrapOrUnwrap) {
      outputParams.tokens = _adjustTokens(outputParams.tokens);
    }

    (outputParams.balancesBefore[0], outputParams.balancesBefore[1]) =
      _recordRouterBalances(msg.sender, outputParams.tokens);
    _computePositionValues(pancakeCL);
  }

  function _computePositionValues(PancakeV4CLParams memory pancakeCL) internal view {
    PositionInfo memory positionInfo = pancakeCL.removeLiqParams.positionInfo;
    RemoveLiquidityParams memory removeLiqParams = pancakeCL.removeLiqParams;

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

    (uint256 feeGrowthInside0, uint256 feeGrowthInside1) = _getFeeGrowthInside(
      pancakeCL.clPoolManager, pancakeCL.poolId, tickLower, tickCurrent, tickUpper
    );

    unchecked {
      positionInfo.unclaimedFees[0] = Math.mulDiv(
        feeGrowthInside0 - positionInfo.feesGrowthInsideLast[0], positionInfo.liquidity, Q128
      );
      positionInfo.unclaimedFees[1] = Math.mulDiv(
        feeGrowthInside1 - positionInfo.feesGrowthInsideLast[1], positionInfo.liquidity, Q128
      );
    }
  }

  function _getFeeGrowthInside(
    ICLPoolManager clPoolManager,
    PoolId poolId,
    int24 tickLower,
    int24 tickCurrent,
    int24 tickUpper
  ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
    (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) =
      clPoolManager.getFeeGrowthGlobals(poolId);

    TickInfo memory lower = clPoolManager.getPoolTickInfo(poolId, tickLower);
    TickInfo memory upper = clPoolManager.getPoolTickInfo(poolId, tickUpper);

    uint256 feeGrowthBelow0X128;
    uint256 feeGrowthBelow1X128;
    unchecked {
      if (tickCurrent >= tickLower) {
        feeGrowthBelow0X128 = lower.feeGrowthOutside0X128;
        feeGrowthBelow1X128 = lower.feeGrowthOutside1X128;
      } else {
        feeGrowthBelow0X128 = feeGrowthGlobal0X128 - lower.feeGrowthOutside0X128;
        feeGrowthBelow1X128 = feeGrowthGlobal1X128 - lower.feeGrowthOutside1X128;
      }

      uint256 feeGrowthAbove0X128;
      uint256 feeGrowthAbove1X128;
      if (tickCurrent < tickUpper) {
        feeGrowthAbove0X128 = upper.feeGrowthOutside0X128;
        feeGrowthAbove1X128 = upper.feeGrowthOutside1X128;
      } else {
        feeGrowthAbove0X128 = feeGrowthGlobal0X128 - upper.feeGrowthOutside0X128;
        feeGrowthAbove1X128 = feeGrowthGlobal1X128 - upper.feeGrowthOutside1X128;
      }

      feeGrowthInside0X128 = feeGrowthGlobal0X128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;
      feeGrowthInside1X128 = feeGrowthGlobal1X128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;
    }
  }

  function _toId(PoolKey memory poolKey) internal pure returns (PoolId poolId) {
    assembly ('memory-safe') {
      poolId := keccak256(poolKey, 0xc0)
    }
  }
}
