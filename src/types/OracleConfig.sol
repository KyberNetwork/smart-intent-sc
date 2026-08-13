// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IERC20Metadata} from 'openzeppelin-contracts/contracts/interfaces/IERC20Metadata.sol';
import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';

import {IOracleAdapter} from '../interfaces/oracle/IOracleAdapter.sol';
import {BoolAddress} from './BoolAddress.sol';
import {OracleSource} from './OracleSource.sol';
import {PackedU128, PackedU128Library} from './PackedU128.sol';

using OracleLib for TokenOracle global;
using OracleLib for OracleConfig global;

/**
 * @notice Oracle for a single token or a direct pair.
 * @param adapter Packed inverse flag and oracle adapter address. Zero address = empty leg.
 * @param source Packed max price staleness in seconds and provider contract
 *        (maxStaleness 96bits | source 160bits).
 * @param priceLimits Normalized price band per whole base token, 1e18-scaled (min 128bits | max 128bits).
 * @param additionalData Adapter-specific data.
 */
struct TokenOracle {
  BoolAddress adapter;
  OracleSource source;
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
  error InvalidMaxDeviation();
  error OraclePriceOutOfRange(uint256 price, uint128 minPrice, uint128 maxPrice);
  error OracleRatioOutOfRange(uint256 ratio, uint128 minRatio, uint128 maxRatio);
  error RealizedPriceBelowOracle(uint256 realizedPrice, uint256 minRealizedPrice);

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

  function hasOracle(OracleConfig calldata config) internal pure returns (bool) {
    return !config.oracleIn.isEmpty() || !config.oracleOut.isEmpty();
  }

  function isEmpty(TokenOracle calldata oracle) internal pure returns (bool) {
    return oracle.adapter.addressValue() == address(0);
  }

  /// @notice Returns the oracle price, reverting if it is outside its configured band.
  /// @dev Empty oracle slots return identity price 1e18.
  function getPriceAndValidate(TokenOracle calldata oracle) internal view returns (uint256 price) {
    if (oracle.isEmpty()) return PRECISION;
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
    priceIn = config.oracleIn.isEmpty() ? PRECISION : config.oracleIn.getPrice();
    priceOut = config.oracleOut.isEmpty() ? PRECISION : config.oracleOut.getPrice();
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

  function getPrice(TokenOracle calldata oracle) internal view returns (uint256 price) {
    (bool inverse, address adapter) = oracle.adapter.unpack();

    price = IOracleAdapter(adapter).getPrice(oracle);
    if (price == 0) revert IOracleAdapter.InvalidOraclePrice();

    if (inverse) {
      return Math.mulDiv(PRECISION, PRECISION, price);
    }
    return price;
  }
}
