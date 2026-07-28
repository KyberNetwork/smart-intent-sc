// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IERC20Metadata} from 'openzeppelin-contracts/contracts/interfaces/IERC20Metadata.sol';
import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';

import {AggregatorV3Interface} from '../interfaces/oracle/external/AggregatorV3Interface.sol';
import {IPyth} from '../interfaces/oracle/external/IPyth.sol';
import {BoolAddress} from './BoolAddress.sol';
import {OraclePackedParam, OracleType} from './OraclePackedParam.sol';
import {PackedU128, PackedU128Library} from './PackedU128.sol';
import {CalldataDecoder} from 'ks-common-sc/src/libraries/calldata/CalldataDecoder.sol';

using OracleLib for TokenOracle global;
using OracleLib for OracleConfig global;

/**
 * @notice Oracle for a single token or a direct pair.
 * @param packedParam Packed oracle type and max price staleness in seconds
 *        (oracleType 8bits | maxStaleness 128bits).
 * @param source Packed inverse flag and Chainlink feed or Pyth contract. Zero address = no oracle for this slot.
 * @param priceLimits Normalized price band per whole base token, 1e18-scaled (min 128bits | max 128bits).
 * @param additionalData Oracle-specific data. For PYTH: word 0 = feed id (bytes32),
 *        word 1 = max confidence-to-price ratio, 1e18-scaled.
 */
struct TokenOracle {
  OraclePackedParam packedParam;
  BoolAddress source;
  PackedU128 priceLimits;
  bytes additionalData;
}

/**
 * @param oracleIn First price edge.
 * @param oracleOut Second price edge.
 * @param oracleRatioLimits Derived B/A oracle ratio band in raw swap-price units.
 * @param maxDeviation Max deviation below the oracle ratio, scaled by 1e18 (0 disables slippage guard).
 */
struct OracleConfig {
  TokenOracle oracleIn;
  TokenOracle oracleOut;
  PackedU128 oracleRatioLimits;
  uint256 maxDeviation;
}

library OracleLib {
  using CalldataDecoder for *;

  error InvalidOraclePrice();
  error InvalidOracleType();
  error InvalidMaxDeviation();
  error OracleConfidenceTooWide(uint256 conf, uint256 price, uint256 maxConfRatio);
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
    uint256 maxDeviation = config.maxDeviation;
    require(maxDeviation <= PRECISION, InvalidMaxDeviation());

    uint256 priceIn = config.oracleIn.getPriceAndValidate();
    uint256 priceOut = config.oracleOut.getPriceAndValidate();

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
  function getPriceAndValidate(TokenOracle calldata oracle) internal view returns (uint256 price) {
    if (oracle.source.addressValue() == address(0)) return PRECISION;
    price = oracle.getPrice();
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
    priceIn = config.oracleIn.source.addressValue() == address(0)
      ? PRECISION
      : config.oracleIn.getPrice();
    priceOut = config.oracleOut.source.addressValue() == address(0)
      ? PRECISION
      : config.oracleOut.getPrice();
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
  function getPrice(TokenOracle calldata oracle) internal view returns (uint256 price) {
    (bool inverse, address source) = oracle.source.unpack();
    (OracleType oracleType, uint256 maxStaleness) = oracle.packedParam.unpack();
    if (oracleType == OracleType.CHAINLINK) {
      (, int256 answer,, uint256 updatedAt,) = AggregatorV3Interface(source).latestRoundData();
      if (answer <= 0) revert InvalidOraclePrice();
      if (block.timestamp - updatedAt > maxStaleness) {
        revert StaleOraclePrice();
      }
      uint8 feedDecimals = AggregatorV3Interface(source).decimals();
      price = Math.mulDiv(uint256(answer), PRECISION, 10 ** feedDecimals);
    } else if (oracleType == OracleType.PYTH) {
      IPyth.Price memory pythPrice =
        IPyth(source).getPriceNoOlderThan(oracle.additionalData.decodeBytes32(), maxStaleness);
      if (pythPrice.price <= 0) revert InvalidOraclePrice();

      uint256 rawPrice = uint256(uint64(pythPrice.price));

      uint256 maxConfRatio = oracle.additionalData.decodeUint256(1);
      uint256 confRatio = Math.mulDiv(uint256(pythPrice.conf), PRECISION, rawPrice);
      if (confRatio > maxConfRatio) {
        revert OracleConfidenceTooWide(pythPrice.conf, rawPrice, maxConfRatio);
      }

      int256 exponent = int256(pythPrice.expo) + 18;
      if (exponent >= 0) {
        price = rawPrice * (10 ** uint256(exponent));
      } else {
        price = rawPrice / (10 ** uint256(-exponent));
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
