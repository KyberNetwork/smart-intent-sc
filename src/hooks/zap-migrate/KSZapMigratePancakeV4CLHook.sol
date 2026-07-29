// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {BaseStatefulHook} from '../base/BaseStatefulHook.sol';
import {BaseTickBasedZapMigrateHook} from '../base/BaseTickBasedZapMigrateHook.sol';

import {ActionData} from '../../types/ActionData.sol';
import {IntentData} from '../../types/IntentData.sol';

import {ICLPoolManager} from '../../interfaces/pancakev4/ICLPoolManager.sol';
import {ICLPositionManager} from '../../interfaces/pancakev4/ICLPositionManager.sol';
import {PoolId, PoolKey, TickInfo} from '../../interfaces/pancakev4/Types.sol';

import {FixedPoint128} from '../../libraries/uniswapv4/FixedPoint128.sol';
import {LiquidityAmounts} from '../../libraries/uniswapv4/LiquidityAmounts.sol';
import {TickMath} from '../../libraries/uniswapv4/TickMath.sol';

import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';

contract KSZapMigrateUniswapV3Hook is BaseTickBasedZapMigrateHook {
  constructor(address[] memory initialRouters) BaseStatefulHook(initialRouters) {}

  function _getPoolAndPositionInfo(address nftAddress, uint256 nftId)
    internal
    view
    override
    returns (PoolAndPositionInfo memory ppInfo)
  {
    PoolKey memory poolKey;
    uint256 feeGrowthInside0Last;
    uint256 feeGrowthInside1Last;
    uint128 positionLiquidity;
    (
      poolKey,
      ppInfo.tickLower,
      ppInfo.tickUpper,
      positionLiquidity,
      feeGrowthInside0Last,
      feeGrowthInside1Last,
    ) = ICLPositionManager(nftAddress).positions(nftId);

    PoolId poolId = _toId(poolKey);
    ppInfo.poolUniqueId = PoolId.unwrap(poolId);

    ppInfo.token0 = poolKey.currency0;
    ppInfo.token1 = poolKey.currency1;
    (ppInfo.sqrtPriceX96, ppInfo.tick,,) = ICLPoolManager(poolKey.poolManager).getSlot0(poolId);

    (uint256 feeGrowthInside0, uint256 feeGrowthInside1) = _getFeeGrowthInside(
      ICLPoolManager(poolKey.poolManager), poolId, ppInfo.tickLower, ppInfo.tick, ppInfo.tickUpper
    );

    (ppInfo.amount0, ppInfo.amount1) = LiquidityAmounts.getAmountsForLiquidity(
      ppInfo.sqrtPriceX96,
      TickMath.getSqrtRatioAtTick(ppInfo.tickLower),
      TickMath.getSqrtRatioAtTick(ppInfo.tickUpper),
      positionLiquidity
    );

    unchecked {
      ppInfo.amount0 += Math.mulDiv(
        feeGrowthInside0 - feeGrowthInside0Last, positionLiquidity, FixedPoint128.Q128
      );
      ppInfo.amount1 += Math.mulDiv(
        feeGrowthInside1 - feeGrowthInside1Last, positionLiquidity, FixedPoint128.Q128
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

  function _getAdditionalData(address nftAddress)
    internal
    view
    override
    returns (bytes memory additionalData)
  {}

  function _getNewNftId(address nftAddress, bytes memory)
    internal
    view
    override
    returns (uint256 newNftId)
  {
    return ICLPositionManager(nftAddress).nextTokenId() - 1;
  }

  function _toId(PoolKey memory poolKey) internal pure returns (PoolId poolId) {
    assembly ('memory-safe') {
      poolId := keccak256(poolKey, 0xc0)
    }
  }
}
