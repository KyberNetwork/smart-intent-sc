// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IOracleAdapter} from '../interfaces/oracle/IOracleAdapter.sol';
import {AggregatorV3Interface} from '../interfaces/oracle/external/AggregatorV3Interface.sol';
import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import {OracleLib, TokenOracle} from 'src/types/OracleConfig.sol';

/// @notice Reads a Chainlink aggregator through the shared `IOracleAdapter` interface.
contract ChainlinkOracleAdapter is IOracleAdapter {
  /**
   * @inheritdoc IOracleAdapter
   */
  function getPrice(TokenOracle calldata oracle) external view returns (uint256 price) {
    (uint256 maxStaleness, address source) = oracle.source.unpack();

    (, int256 answer,, uint256 updatedAt,) = AggregatorV3Interface(source).latestRoundData();
    if (answer <= 0) revert InvalidOraclePrice();
    if (block.timestamp - updatedAt > maxStaleness) revert StaleOraclePrice();

    uint8 feedDecimals = AggregatorV3Interface(source).decimals();
    price = Math.mulDiv(uint256(answer), OracleLib.PRECISION, 10 ** feedDecimals);
    if (price == 0) revert InvalidOraclePrice();
  }
}
