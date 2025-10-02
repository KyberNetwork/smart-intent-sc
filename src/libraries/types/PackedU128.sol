// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import 'src/constants/BitMask.sol';

/**
 * @notice two 128-bit values packed into a 256-bit value
 * where the first 128 bits are the first value
 * and the last 128 bits are the second value.
 */
type PackedU128 is uint256;

using PackedU128Library for PackedU128 global;

/**
 * @notice pack two 128-bit values into a 256-bit value
 * @dev use 256-bit params for versatility
 */
function toPackedU128(uint256 value0, uint256 value1) pure returns (PackedU128 packedU128) {
  assembly ("memory-safe") {
    packedU128 := or(shl(128, value0), value1)
  }
}

library PackedU128Library {
  /// @notice get the first 128 bits of the packed value
  function value0(PackedU128 packedU128) internal pure returns (uint128 _value0) {
    assembly ("memory-safe") {
      _value0 := shr(128, packedU128)
    }
  }

  /// @notice get the last 128 bits of the packed value
  function value1(PackedU128 packedU128) internal pure returns (uint128 _value1) {
    assembly ("memory-safe") {
      _value1 := and(packedU128, MASK_128_BITS)
    }
  }

  /// @notice unpack the packed value into two 128-bit values
  function unpack(PackedU128 packedU128) internal pure returns (uint128 _value0, uint128 _value1) {
    assembly ("memory-safe") {
      _value0 := shr(128, packedU128)
      _value1 := and(packedU128, MASK_128_BITS)
    }
  }
}
