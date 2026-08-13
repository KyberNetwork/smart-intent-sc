// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MASK_160_BITS, MASK_96_BITS} from '../libraries/BitMask.sol';

/**
 * @notice A packed max price staleness and oracle source address.
 *
 * Layout: 96 bits max staleness (seconds) | 160 bits source address
 */
type OracleSource is uint256;

using OracleSourceLibrary for OracleSource global;

uint256 constant MAX_STALENESS_OFFSET = 160;

function toOracleSource(uint256 maxStaleness, address source) pure returns (OracleSource result) {
  assembly ('memory-safe') {
    result := or(shl(MAX_STALENESS_OFFSET, and(maxStaleness, MASK_96_BITS)), source)
  }
}

library OracleSourceLibrary {
  function maxStaleness(OracleSource self) internal pure returns (uint256 _maxStaleness) {
    assembly ('memory-safe') {
      _maxStaleness := shr(MAX_STALENESS_OFFSET, self)
    }
  }

  function source(OracleSource self) internal pure returns (address _source) {
    assembly ('memory-safe') {
      _source := and(self, MASK_160_BITS)
    }
  }

  function unpack(OracleSource self)
    internal
    pure
    returns (uint256 _maxStaleness, address _source)
  {
    assembly ('memory-safe') {
      _maxStaleness := shr(MAX_STALENESS_OFFSET, self)
      _source := and(self, MASK_160_BITS)
    }
  }
}
