// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import 'src/interfaces/uniswapv4/IPoolManager.sol';
import 'src/interfaces/uniswapv4/IPositionManager.sol';
import 'src/libraries/uniswapv4/LiquidityAmounts.sol';
import 'src/libraries/uniswapv4/TickMath.sol';

/// @notice A helper library to provide state getters that use extsload
library StateLibrary {
  using StateLibrary for IPoolManager;

  /// @notice index of pools mapping in the PoolManager
  bytes32 public constant POOLS_SLOT = bytes32(uint256(6));

  /// @notice index of feeGrowthGlobal0X128 in Pool.State
  uint256 public constant FEE_GROWTH_GLOBAL0_OFFSET = 1;

  // feeGrowthGlobal1X128 offset in Pool.State = 2

  /// @notice index of liquidity in Pool.State
  uint256 public constant LIQUIDITY_OFFSET = 3;

  /// @notice index of TicksInfo mapping in Pool.State: mapping(int24 => TickInfo) ticks;
  uint256 public constant TICKS_OFFSET = 4;

  /// @notice index of tickBitmap mapping in Pool.State
  uint256 public constant TICK_BITMAP_OFFSET = 5;

  /// @notice index of Position.State mapping in Pool.State: mapping(bytes32 => Position.State) positions;
  uint256 public constant POSITIONS_OFFSET = 6;

  uint256 public constant Q128 = 1 << 128;

  function computePositionValues(
    IPoolManager poolManager,
    IPositionManager positionManager,
    uint256 tokenId,
    uint256 liquidityToRemove
  )
    internal
    view
    returns (uint256 amount0, uint256 amount1, uint256 unclaimedFee0, uint256 unclaimedFee1)
  {
    (PoolKey memory poolKey, uint256 positionInfo) = positionManager.getPoolAndPositionInfo(tokenId);
    bytes32 poolId = getPoolId(poolKey);
    (uint160 sqrtPriceX96, int24 tickCurrent,,) = poolManager.getSlot0(poolId);
    (int24 tickLower, int24 tickUpper) = StateLibrary.getTickRange(positionInfo);

    if (liquidityToRemove != 0) {
      uint160 sqrtPriceLower = TickMath.getSqrtRatioAtTick(tickLower);
      uint160 sqrtPriceUpper = TickMath.getSqrtRatioAtTick(tickUpper);
      (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
        sqrtPriceX96, sqrtPriceLower, sqrtPriceUpper, uint128(liquidityToRemove)
      );
    }
    bytes32 positionKey = StateLibrary.calculatePositionKey(
      address(positionManager), tickLower, tickUpper, bytes32(tokenId)
    );

    (uint256 positionLiquidity, uint256 feeGrowthInside0Last, uint256 feeGrowthInside1Last) =
      poolManager.getPositionInfo(poolId, positionKey);

    (uint256 feeGrowthInside0, uint256 feeGrowthInside1) =
      poolManager.getFeeGrowthInside(poolId, tickLower, tickUpper, tickCurrent);

    unchecked {
      unclaimedFee0 = Math.mulDiv(feeGrowthInside0 - feeGrowthInside0Last, positionLiquidity, Q128);
      unclaimedFee1 = Math.mulDiv(feeGrowthInside1 - feeGrowthInside1Last, positionLiquidity, Q128);
    }
  }

  function getFeeGrowthInside(
    IPoolManager poolManager,
    bytes32 poolId,
    int24 tickLower,
    int24 tickUpper,
    int24 tickCurrent
  ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
    (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) =
      poolManager.getFeeGrowthGlobals(poolId);
    (uint256 feeGrowthOutside0X128Lower, uint256 feeGrowthOutside1X128Lower) =
      poolManager.getTickFeeGrowthOutside(poolId, tickLower);
    (uint256 feeGrowthOutside0X128Upper, uint256 feeGrowthOutside1X128Upper) =
      poolManager.getTickFeeGrowthOutside(poolId, tickUpper);

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

  function getPoolId(PoolKey memory poolKey) internal pure returns (bytes32 poolId) {
    assembly {
      poolId := keccak256(poolKey, 0xa0)
    }
  }

  /**
   * @notice Get Slot0 of the pool: sqrtPriceX96, tick, protocolFee, lpFee
   * @dev Corresponds to pools[poolId].slot0
   * @param manager The pool manager contract.
   * @param poolId The ID of the pool.
   * @return sqrtPriceX96 The square root of the price of the pool, in Q96 precision.
   * @return tick The current tick of the pool.
   * @return protocolFee The protocol fee of the pool.
   * @return lpFee The swap fee of the pool.
   */
  function getSlot0(IPoolManager manager, bytes32 poolId)
    internal
    view
    returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)
  {
    // slot key of Pool.State value: `pools[poolId]`
    bytes32 stateSlot = _getPoolStateSlot(poolId);

    bytes32 data = manager.extsload(stateSlot);

    //   24 bits  |24bits|24bits      |24 bits|160 bits
    // 0x000000   |000bb8|000000      |ffff75 |0000000000000000fe3aa841ba359daa0ea9eff7
    // ---------- | fee  |protocolfee | tick  | sqrtPriceX96
    assembly {
      // bottom 160 bits of data
      sqrtPriceX96 := and(data, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
      // next 24 bits of data
      tick := signextend(2, shr(160, data))
      // next 24 bits of data
      protocolFee := and(shr(184, data), 0xFFFFFF)
      // last 24 bits of data
      lpFee := and(shr(208, data), 0xFFFFFF)
    }
  }

  /**
   * @notice Retrieves the position information of a pool at a specific position ID.
   * @dev Corresponds to pools[poolId].positions[positionId]
   * @param manager The pool manager contract.
   * @param poolId The ID of the pool.
   * @param positionId The ID of the position.
   * @return liquidity The liquidity of the position.
   * @return feeGrowthInside0LastX128 The fee growth inside the position for token0.
   * @return feeGrowthInside1LastX128 The fee growth inside the position for token1.
   */
  function getPositionInfo(IPoolManager manager, bytes32 poolId, bytes32 positionId)
    internal
    view
    returns (uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128)
  {
    bytes32 slot = _getPositionInfoSlot(poolId, positionId);

    // read all 3 words of the Position.State struct
    bytes32[] memory data = manager.extsload(slot, 3);

    assembly {
      liquidity := mload(add(data, 32))
      feeGrowthInside0LastX128 := mload(add(data, 64))
      feeGrowthInside1LastX128 := mload(add(data, 96))
    }
  }

  /// @notice A helper function to calculate the position key
  /// @param owner The address of the position owner
  /// @param tickLower the lower tick boundary of the position
  /// @param tickUpper the upper tick boundary of the position
  /// @param salt A unique value to differentiate between multiple positions in the same range, by the same owner. Passed in by the caller.
  function calculatePositionKey(address owner, int24 tickLower, int24 tickUpper, bytes32 salt)
    internal
    pure
    returns (bytes32 positionKey)
  {
    // positionKey = keccak256(abi.encodePacked(owner, tickLower, tickUpper, salt))
    assembly {
      let fmp := mload(0x40)
      mstore(add(fmp, 0x26), salt) // [0x26, 0x46)
      mstore(add(fmp, 0x06), tickUpper) // [0x23, 0x26)
      mstore(add(fmp, 0x03), tickLower) // [0x20, 0x23)
      mstore(fmp, owner) // [0x0c, 0x20)
      positionKey := keccak256(add(fmp, 0x0c), 0x3a) // len is 58 bytes

      // now clean the memory we used
      mstore(add(fmp, 0x40), 0) // fmp+0x40 held salt
      mstore(add(fmp, 0x20), 0) // fmp+0x20 held tickLower, tickUpper, salt
      mstore(fmp, 0) // fmp held owner
    }
  }

  /**
   * @notice Retrieves the global fee growth of a pool.
   * @dev Corresponds to pools[poolId].feeGrowthGlobal0X128 and pools[poolId].feeGrowthGlobal1X128
   * @param manager The pool manager contract.
   * @param poolId The ID of the pool.
   * @return feeGrowthGlobal0 The global fee growth for token0.
   * @return feeGrowthGlobal1 The global fee growth for token1.
   */
  function getFeeGrowthGlobals(IPoolManager manager, bytes32 poolId)
    internal
    view
    returns (uint256 feeGrowthGlobal0, uint256 feeGrowthGlobal1)
  {
    // slot key of Pool.State value: `pools[poolId]`
    bytes32 stateSlot = _getPoolStateSlot(poolId);

    // Pool.State, `uint256 feeGrowthGlobal0X128`
    bytes32 slot_feeGrowthGlobal0X128 = bytes32(uint256(stateSlot) + FEE_GROWTH_GLOBAL0_OFFSET);

    // read the 2 words of feeGrowthGlobal
    bytes32[] memory data = manager.extsload(slot_feeGrowthGlobal0X128, 2);
    assembly {
      feeGrowthGlobal0 := mload(add(data, 32))
      feeGrowthGlobal1 := mload(add(data, 64))
    }
  }

  /**
   * @notice Retrieves the fee growth outside a tick range of a pool
   * @dev Corresponds to pools[poolId].ticks[tick].feeGrowthOutside0X128 and pools[poolId].ticks[tick].feeGrowthOutside1X128. A more gas efficient version of getTickInfo
   * @param manager The pool manager contract.
   * @param poolId The ID of the pool.
   * @param tick The tick to retrieve fee growth for.
   * @return feeGrowthOutside0X128 fee growth per unit of liquidity on the _other_ side of this tick (relative to the current tick)
   * @return feeGrowthOutside1X128 fee growth per unit of liquidity on the _other_ side of this tick (relative to the current tick)
   */
  function getTickFeeGrowthOutside(IPoolManager manager, bytes32 poolId, int24 tick)
    internal
    view
    returns (uint256 feeGrowthOutside0X128, uint256 feeGrowthOutside1X128)
  {
    bytes32 slot = _getTickInfoSlot(poolId, tick);

    // offset by 1 word, since the first word is liquidityGross + liquidityNet
    bytes32[] memory data = manager.extsload(bytes32(uint256(slot) + 1), 2);
    assembly {
      feeGrowthOutside0X128 := mload(add(data, 32))
      feeGrowthOutside1X128 := mload(add(data, 64))
    }
  }

  function _getPositionInfoSlot(bytes32 poolId, bytes32 positionId) internal pure returns (bytes32) {
    // slot key of Pool.State value: `pools[poolId]`
    bytes32 stateSlot = _getPoolStateSlot(poolId);

    // Pool.State: `mapping(bytes32 => Position.State) positions;`
    bytes32 positionMapping = bytes32(uint256(stateSlot) + POSITIONS_OFFSET);

    // slot of the mapping key: `pools[poolId].positions[positionId]
    return keccak256(abi.encodePacked(positionId, positionMapping));
  }

  function _getTickInfoSlot(bytes32 poolId, int24 tick) internal pure returns (bytes32) {
    // slot key of Pool.State value: `pools[poolId]`
    bytes32 stateSlot = _getPoolStateSlot(poolId);

    // Pool.State: `mapping(int24 => TickInfo) ticks`
    bytes32 ticksMappingSlot = bytes32(uint256(stateSlot) + TICKS_OFFSET);

    // slot key of the tick key: `pools[poolId].ticks[tick]
    return keccak256(abi.encodePacked(int256(tick), ticksMappingSlot));
  }

  function _getPoolStateSlot(bytes32 poolId) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(poolId, POOLS_SLOT));
  }

  function getTickRange(uint256 posInfo) internal pure returns (int24 _tickLower, int24 _tickUpper) {
    assembly {
      _tickLower := signextend(2, shr(8, posInfo))
      _tickUpper := signextend(2, shr(32, posInfo))
    }
  }
}
