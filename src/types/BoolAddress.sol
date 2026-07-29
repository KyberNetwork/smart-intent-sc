// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MASK_160_BITS} from '../libraries/BitMask.sol';

/**
 * @notice A packed boolean and address value.
 *
 * Layout: 1 bit boolean value | 160 bits address value
 */
type BoolAddress is uint256;

using BoolAddressLibrary for BoolAddress global;

function toBoolAddress(bool boolValue, address addressValue) pure returns (BoolAddress result) {
  assembly ('memory-safe') {
    result := or(shl(160, boolValue), addressValue)
  }
}

library BoolAddressLibrary {
  uint256 internal constant BOOL_VALUE_OFFSET = 160;

  function boolValue(BoolAddress self) internal pure returns (bool _boolValue) {
    assembly ('memory-safe') {
      _boolValue := shr(BOOL_VALUE_OFFSET, self)
    }
  }

  function addressValue(BoolAddress self) internal pure returns (address _addressValue) {
    assembly ('memory-safe') {
      _addressValue := and(self, MASK_160_BITS)
    }
  }

  function unpack(BoolAddress self) internal pure returns (bool _boolValue, address _addressValue) {
    assembly ('memory-safe') {
      _boolValue := shr(BOOL_VALUE_OFFSET, self)
      _addressValue := and(self, MASK_160_BITS)
    }
  }
}
