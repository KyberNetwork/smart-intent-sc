// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {BaseStatefulHook} from '../base/BaseStatefulHook.sol';
import {BaseTickBasedZapMigrateHook} from '../base/BaseTickBasedZapMigrateHook.sol';

import {ActionData} from '../../types/ActionData.sol';
import {IntentData} from '../../types/IntentData.sol';

import {IUniswapV3Factory} from '../../interfaces/uniswapv3/IUniswapV3Factory.sol';
import {IUniswapV3PM} from '../../interfaces/uniswapv3/IUniswapV3PM.sol';
import {IUniswapV3Pool} from '../../interfaces/uniswapv3/IUniswapV3Pool.sol';

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
    uint24 fee;
    uint128 liquidity;
    uint256 feeGrowthInside0LastX128;
    uint256 feeGrowthInside1LastX128;
    (
      ,,
      ppInfo.token0,
      ppInfo.token1,
      fee,
      ppInfo.tickLower,
      ppInfo.tickUpper,
      liquidity,
      feeGrowthInside0LastX128,
      feeGrowthInside1LastX128,,
    ) = IUniswapV3PM(nftAddress).positions(nftId);

    IUniswapV3Pool pool = IUniswapV3Pool(
      IUniswapV3Factory(IUniswapV3PM(nftAddress).factory())
        .getPool(ppInfo.token0, ppInfo.token1, fee)
    );
    ppInfo.poolUniqueId = bytes32(uint256(uint160(address(pool))));

    (ppInfo.sqrtPriceX96, ppInfo.tick,,,,,) = pool.slot0();

    (ppInfo.amount0, ppInfo.amount1) = LiquidityAmounts.getAmountsForLiquidity(
      ppInfo.sqrtPriceX96,
      TickMath.getSqrtRatioAtTick(ppInfo.tickLower),
      TickMath.getSqrtRatioAtTick(ppInfo.tickUpper),
      liquidity
    );

    (uint256 feeGrowthInside0, uint256 feeGrowthInside1) =
      _getFeeGrowthInside(pool, ppInfo.tickLower, ppInfo.tick, ppInfo.tickUpper);

    unchecked {
      ppInfo.amount0 += Math.mulDiv(
        feeGrowthInside0 - feeGrowthInside0LastX128, liquidity, FixedPoint128.Q128
      );
      ppInfo.amount1 += Math.mulDiv(
        feeGrowthInside1 - feeGrowthInside1LastX128, liquidity, FixedPoint128.Q128
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

  function _getNewNftId(address nftAddress, bytes memory additionalData)
    internal
    view
    override
    returns (uint256 newNftId)
  {
    uint256 index = abi.decode(additionalData, (uint256));
    return IUniswapV3PM(nftAddress).tokenByIndex(index);
  }
}
