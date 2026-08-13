// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {TokenOracle} from '../../types/OracleConfig.sol';

interface IOracleAdapter {
  /// @notice The source reported a non-positive or unusable price.
  error InvalidOraclePrice();
  /// @notice The source's price is older than `maxStaleness`.
  error StaleOraclePrice();

  /**
   * @notice Price of one whole base token, normalized to 1e18.
   * @param oracle The oracle info
   * @return price Normalized price, always non-zero. The caller applies the `inverse` flag.
   */
  function getPrice(TokenOracle calldata oracle) external view returns (uint256 price);
}
