// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2024 PancakeSwap
pragma solidity ^0.8.0;

/**
 * @title Concentrated Liquidity Pair Parameter Helper Library
 * @dev This library contains functions to get and set parameters of a pair
 * The parameters are stored in a single bytes32 variable in the following format:
 *
 * [0 - 15[: reserve for hooks
 * [16 - 39[: tickSpacing (24 bits)
 * [40 - 256[: unused
 */
library CLPoolParametersHelper {
  uint256 internal constant OFFSET_TICK_SPACING = 16;
  uint256 internal constant OFFSET_MOST_SIGNIFICANT_UNUSED_BITS = 40;

  /**
   * @dev Get tickSpacing from the encoded pair parameters
   * @param params The encoded pair parameters, as follows:
   * [0 - 16[: hooks registration bitmaps
   * [16 - 39[: tickSpacing (24 bits)
   * [40 - 256[: unused
   * @return tickSpacing The tickSpacing
   */
  function getTickSpacing(bytes32 params) internal pure returns (int24 tickSpacing) {
    assembly ('memory-safe') {
      tickSpacing := and(shr(OFFSET_TICK_SPACING, params), 0xFFFFFF)
    }
  }
}
