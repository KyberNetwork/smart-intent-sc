//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

type PoolId is bytes32;

type BalanceDelta is int256;

type PositionInfo is uint256;

/// @notice Returns the key for identifying a pool
struct PoolKey {
  /// @notice The lower currency of the pool, sorted numerically
  address currency0;
  /// @notice The higher currency of the pool, sorted numerically
  address currency1;
  /// @notice The pool LP fee, capped at 1_000_000. If the highest bit is 1, the pool has a dynamic fee and must be exactly equal to 0x800000
  uint24 fee;
  /// @notice Ticks that involve positions must be a multiple of tick spacing
  int24 tickSpacing;
  /// @notice The hooks of the pool
  address hooks;
}

/// @notice Library to define different pool actions.
/// @dev These are suggested common commands, however additional commands should be defined as required
library Actions {
  // pool actions
  // liquidity actions
  uint256 constant INCREASE_LIQUIDITY = 0x00;
  uint256 constant DECREASE_LIQUIDITY = 0x01;
  uint256 constant MINT_POSITION = 0x02;
  uint256 constant BURN_POSITION = 0x03;
  uint256 constant INCREASE_LIQUIDITY_FROM_DELTAS = 0x04;
  uint256 constant MINT_POSITION_FROM_DELTAS = 0x05;

  // swapping
  uint256 constant SWAP_EXACT_IN_SINGLE = 0x06;
  uint256 constant SWAP_EXACT_IN = 0x07;
  uint256 constant SWAP_EXACT_OUT_SINGLE = 0x08;
  uint256 constant SWAP_EXACT_OUT = 0x09;
  // donate
  uint256 constant DONATE = 0x0a;

  // closing deltas on the pool manager
  // settling
  uint256 constant SETTLE = 0x0b;
  uint256 constant SETTLE_ALL = 0x0c;
  uint256 constant SETTLE_PAIR = 0x0d;
  // taking
  uint256 constant TAKE = 0x0e;
  uint256 constant TAKE_ALL = 0x0f;
  uint256 constant TAKE_PORTION = 0x10;
  uint256 constant TAKE_PAIR = 0x11;

  uint256 constant CLOSE_CURRENCY = 0x12;
  uint256 constant CLEAR_OR_TAKE = 0x13;
  uint256 constant SWEEP = 0x14;

  uint256 constant WRAP = 0x15;
  uint256 constant UNWRAP = 0x16;

  // minting/burning 6909s to close deltas
  uint256 constant MINT_6909 = 0x17;
  uint256 constant BURN_6909 = 0x18;
}

/// @title Commands
/// @notice Command Flags used to decode commands
library Commands {
  uint256 constant SWEEP = 0x04;
  uint256 constant V4_SWAP = 0x10;
}

struct ExactInputSingleParams {
  PoolKey poolKey;
  bool zeroForOne;
  uint128 amountIn;
  uint128 amountOutMinimum;
  bytes hookData;
}
