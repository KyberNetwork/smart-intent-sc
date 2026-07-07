// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IERC20Metadata} from 'openzeppelin-contracts/contracts/interfaces/IERC20Metadata.sol';
import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';

import {AggregatorV3Interface} from '../interfaces/oracle/external/AggregatorV3Interface.sol';
import {IPyth} from '../interfaces/oracle/external/IPyth.sol';
import {BoolAddress} from '../types/BoolAddress.sol';
import {PackedU128, PackedU128Library} from '../types/PackedU128.sol';
import {CalldataDecoder} from 'ks-common-sc/src/libraries/calldata/CalldataDecoder.sol';

using OracleLib for TokenOracle global;
using OracleLib for OracleConfig global;

enum OracleType {
  NONE,
  CHAINLINK,
  PYTH
}

/**
 * @notice Oracle for a single token or a direct pair.
 * @param oracleType type of the oracle.
 * @param source Packed inverse flag and Chainlink feed or Pyth contract. Zero address = no oracle for this slot.
 * @param priceLimits Normalized price band per whole base token, 1e18-scaled (min 128bits | max 128bits).
 * @param additionalData Oracle-specific data.
 */
struct TokenOracle {
  OracleType oracleType;
  BoolAddress source;
  PackedU128 priceLimits;
  bytes additionalData;
}

/**
 * @param oracleIn First price edge.
 * @param oracleOut Second price edge.
 * @param oracleParams maxStaleness 128bits | maxDeviation 128bits, scaled by 1e18 (0 disables slippage guard).
 * @param oracleRatioLimits Derived B/A oracle ratio band in raw swap-price units.
 */
struct OracleConfig {
  TokenOracle oracleIn;
  TokenOracle oracleOut;
  PackedU128 oracleParams;
  PackedU128 oracleRatioLimits;
}

library OracleLib {
  using CalldataDecoder for *;

  error InvalidOraclePrice();
  error InvalidOracleType();
  error InvalidMaxDeviation();
  error OraclePriceOutOfRange(uint256 price, uint128 minPrice, uint128 maxPrice);
  error OracleRatioOutOfRange(uint256 ratio, uint128 minRatio, uint128 maxRatio);
  error RealizedPriceBelowOracle(uint256 realizedPrice, uint256 minRealizedPrice);
  error StaleOraclePrice();

  uint256 internal constant PRECISION = 1e18;

  /**
   * @notice Validates oracle price bands and minimum realized swap price, reverting on failure.
   * @param realizedPrice Raw swap price: `amountOut_raw * 1e18 / amountIn_raw`.
   */
  function validate(
    OracleConfig calldata config,
    address tokenIn,
    address tokenOut,
    uint256 realizedPrice
  ) internal view {
    (uint128 maxStaleness, uint128 maxDeviation) = config.oracleParams.unpack();
    require(maxDeviation <= PRECISION, InvalidMaxDeviation());

    uint256 priceIn = config.oracleIn.getPriceAndValidate(maxStaleness);
    uint256 priceOut = config.oracleOut.getPriceAndValidate(maxStaleness);

    uint256 ratio = _toRawRatio(Math.mulDiv(priceIn, priceOut, PRECISION), tokenIn, tokenOut);
    (uint128 minOracleRatio, uint128 maxOracleRatio) = config.oracleRatioLimits.unpack();
    if (ratio < minOracleRatio || ratio > maxOracleRatio) {
      revert OracleRatioOutOfRange(ratio, minOracleRatio, maxOracleRatio);
    }

    if (maxDeviation != 0 && maxDeviation < PRECISION) {
      uint256 minRealizedPrice = Math.mulDiv(ratio, PRECISION - maxDeviation, PRECISION);
      if (realizedPrice < minRealizedPrice) {
        revert RealizedPriceBelowOracle(realizedPrice, minRealizedPrice);
      }
    }
  }

  /// @notice Returns the oracle price, reverting if it is outside its configured band.
  /// @dev Empty oracle slots return identity price 1e18.
  function getPriceAndValidate(TokenOracle calldata oracle, uint256 maxStaleness)
    internal
    view
    returns (uint256 price)
  {
    if (oracle.source.addressValue() == address(0)) return PRECISION;
    price = oracle.getPrice(maxStaleness);
    (uint128 min, uint128 max) = oracle.priceLimits.unpack();
    if (price < min || price > max) {
      revert OraclePriceOutOfRange(price, min, max);
    }
    return price;
  }

  /// @notice Oracle edge prices (1e18) and the derived raw-basis ratio.
  function getPrices(OracleConfig calldata config, address tokenIn, address tokenOut)
    internal
    view
    returns (uint256 priceIn, uint256 priceOut, uint256 ratio)
  {
    (uint128 maxStaleness,) = config.oracleParams.unpack();
    priceIn = config.oracleIn.source.addressValue() == address(0)
      ? PRECISION
      : config.oracleIn.getPrice(maxStaleness);
    priceOut = config.oracleOut.source.addressValue() == address(0)
      ? PRECISION
      : config.oracleOut.getPrice(maxStaleness);
    ratio = _toRawRatio(Math.mulDiv(priceIn, priceOut, PRECISION), tokenIn, tokenOut);
  }

  /**
   * @dev Converts a whole-token tokenOut/tokenIn ratio to the hook's realized-price unit:
   *      amountOut_raw * 1e18 / amountIn_raw.
   */
  function _toRawRatio(uint256 price, address tokenIn, address tokenOut)
    private
    view
    returns (uint256)
  {
    uint8 decimalsIn = IERC20Metadata(tokenIn).decimals();
    uint8 decimalsOut = IERC20Metadata(tokenOut).decimals();
    if (decimalsOut >= decimalsIn) {
      return price * (10 ** uint256(decimalsOut - decimalsIn));
    }
    return price / (10 ** uint256(decimalsIn - decimalsOut));
  }

  /// @dev Normalized oracle price per whole base token (1e18).
  function getPrice(TokenOracle calldata oracle, uint256 maxStaleness)
    internal
    view
    returns (uint256 price)
  {
    (bool inverse, address source) = oracle.source.unpack();
    if (oracle.oracleType == OracleType.CHAINLINK) {
      (, int256 answer,, uint256 updatedAt,) = AggregatorV3Interface(source).latestRoundData();
      if (answer <= 0) revert InvalidOraclePrice();
      if (block.timestamp - updatedAt > maxStaleness) {
        revert StaleOraclePrice();
      }
      uint8 feedDecimals = AggregatorV3Interface(source).decimals();
      price = Math.mulDiv(uint256(answer), PRECISION, 10 ** feedDecimals);
    } else if (oracle.oracleType == OracleType.PYTH) {
      IPyth.Price memory pythPrice =
        IPyth(source).getPriceNoOlderThan(oracle.additionalData.decodeBytes32(), maxStaleness);
      if (pythPrice.price <= 0) revert InvalidOraclePrice();

      int256 exponent = int256(pythPrice.expo) + 18;
      if (exponent >= 0) {
        price = uint256(uint64(pythPrice.price)) * (10 ** uint256(exponent));
      } else {
        price = uint256(uint64(pythPrice.price)) / (10 ** uint256(-exponent));
      }
    } else {
      revert InvalidOracleType();
    }

    if (inverse) {
      return Math.mulDiv(PRECISION, PRECISION, price);
    }
    return price;
  }
}
