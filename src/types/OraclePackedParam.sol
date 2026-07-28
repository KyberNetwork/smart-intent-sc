// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MASK_128_BITS, MASK_8_BITS} from '../libraries/BitMask.sol';

enum OracleType {
  NONE,
  CHAINLINK,
  PYTH
}

/**
 * @notice A packed oracle type and its max price staleness.
 *
 * Layout: 8 bits oracle type | 128 bits max staleness (seconds)
 */
type OraclePackedParam is uint256;

using OraclePackedParamLibrary for OraclePackedParam global;

uint256 constant ORACLE_TYPE_OFFSET = 128;

/// @notice pack an oracle type and a max staleness (seconds) into a single word
function toOraclePackedParam(OracleType oracleType, uint256 maxStaleness)
  pure
  returns (OraclePackedParam result)
{
  assembly ('memory-safe') {
    result := or(
      shl(ORACLE_TYPE_OFFSET, and(oracleType, MASK_8_BITS)),
      and(maxStaleness, MASK_128_BITS)
    )
  }
}

library OraclePackedParamLibrary {
  /// @notice get the oracle type, reverting if the packed value is not a known type
  function oracleType(OraclePackedParam self) internal pure returns (OracleType) {
    return OracleType((OraclePackedParam.unwrap(self) >> ORACLE_TYPE_OFFSET) & MASK_8_BITS);
  }

  /// @notice get the max accepted age of the oracle price, in seconds
  function maxStaleness(OraclePackedParam self) internal pure returns (uint256 _maxStaleness) {
    assembly ('memory-safe') {
      _maxStaleness := and(self, MASK_128_BITS)
    }
  }

  /// @notice unpack the oracle type and the max staleness
  function unpack(OraclePackedParam self)
    internal
    pure
    returns (OracleType _oracleType, uint256 _maxStaleness)
  {
    _oracleType = oracleType(self);
    _maxStaleness = maxStaleness(self);
  }
}
