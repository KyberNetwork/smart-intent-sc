// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {BaseStatefulHook} from '../base/BaseStatefulHook.sol';
import {BaseTickBasedZapMigrateHook} from '../base/BaseTickBasedZapMigrateHook.sol';

import {ActionData} from '../../types/ActionData.sol';
import {IntentData} from '../../types/IntentData.sol';

import {IPoolManager} from '../../interfaces/uniswapv4/IPoolManager.sol';
import {IPositionManager} from '../../interfaces/uniswapv4/IPositionManager.sol';
import {PoolKey} from '../../interfaces/uniswapv4/Types.sol';

import {FixedPoint128} from '../../libraries/uniswapv4/FixedPoint128.sol';
import {LiquidityAmounts} from '../../libraries/uniswapv4/LiquidityAmounts.sol';
import {StateLibrary} from '../../libraries/uniswapv4/StateLibrary.sol';
import {TickMath} from '../../libraries/uniswapv4/TickMath.sol';

import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';

contract KSZapMigrateUniswapV3Hook is BaseTickBasedZapMigrateHook {
  using StateLibrary for IPoolManager;

  constructor(address[] memory initialRouters) BaseStatefulHook(initialRouters) {}

  function _getPoolAndPositionInfo(address nftAddress, uint256 nftId)
    internal
    view
    override
    returns (PoolAndPositionInfo memory ppInfo)
  {
    (PoolKey memory poolKey, uint256 positionInfo) =
      IPositionManager(nftAddress).getPoolAndPositionInfo(nftId);
    bytes32 poolId = StateLibrary.getPoolId(poolKey);

    IPoolManager poolManager = IPositionManager(nftAddress).poolManager();

    ppInfo.token0 = poolKey.currency0;
    ppInfo.token1 = poolKey.currency1;
    (ppInfo.sqrtPriceX96, ppInfo.tick,,) = poolManager.getSlot0(poolId);
    (ppInfo.tickLower, ppInfo.tickUpper) = StateLibrary.getTickRange(positionInfo);

    bytes32 positionKey = StateLibrary.calculatePositionKey(
      nftAddress, ppInfo.tickLower, ppInfo.tickUpper, bytes32(nftId)
    );
    (uint128 positionLiquidity, uint256 feeGrowthInside0Last, uint256 feeGrowthInside1Last) =
      poolManager.getPositionInfo(poolId, positionKey);
    (uint256 feeGrowthInside0, uint256 feeGrowthInside1) =
      poolManager.getFeeGrowthInside(poolId, ppInfo.tickLower, ppInfo.tickUpper, ppInfo.tick);

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

  function _getNewNftId(address nftAddress, bytes memory)
    internal
    view
    override
    returns (uint256 newNftId)
  {
    return IPositionManager(nftAddress).nextTokenId() - 1;
  }
}
