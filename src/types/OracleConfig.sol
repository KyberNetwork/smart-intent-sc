// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IERC20Metadata} from 'openzeppelin-contracts/contracts/interfaces/IERC20Metadata.sol';
import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';

import {TokenHelper} from 'ks-common-sc/src/libraries/token/TokenHelper.sol';

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
 * @param minRatio Min derived oracle ratio, raw swap-price units scaled by 1e36.
 * @param maxRatio Max derived oracle ratio, raw swap-price units scaled by 1e36.
 * @param maxDeviation Max deviation below the oracle ratio, scaled by 1e18 (0 disables slippage guard).
 */
struct OracleConfig {
  TokenOracle oracleIn;
  TokenOracle oracleOut;
  uint256 minRatio;
  uint256 maxRatio;
  uint256 maxDeviation;
}

library OracleLib {
  error InvalidMaxDeviation();
  error OraclePriceOutOfRange(uint256 price, uint128 minPrice, uint128 maxPrice);
  error OracleRatioOutOfRange(uint256 ratio, uint256 minRatio, uint256 maxRatio);
  error RealizedPriceBelowOracle(uint256 realizedPrice, uint256 minRealizedPrice);

  /// @dev Scale of oracle edge prices and `maxDeviation`
  uint256 internal constant PRECISION = 1e18;

  /**
   * @notice Validates oracle price bands and minimum realized swap price, reverting on failure.
   * @param realizedPrice Raw swap price: `amountOut_raw * 1e36 / amountIn_raw`.
   */
  function validate(
    OracleConfig calldata config,
    address tokenIn,
    address tokenOut,
    uint256 realizedPrice
  ) internal view {
    uint256 maxDeviation = config.maxDeviation;
    require(maxDeviation <= PRECISION, InvalidMaxDeviation());

    (,, uint256 ratio) = config.getPrices(tokenIn, tokenOut);
    if (ratio < config.minRatio || ratio > config.maxRatio) {
      revert OracleRatioOutOfRange(ratio, config.minRatio, config.maxRatio);
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

  /**
   * @notice Oracle edge prices (1e18) and the derived ratio in raw swap-price units scaled by 1e36,
   *         reverting if any edge is out of band.
   */
  function getPrices(OracleConfig calldata config, address tokenIn, address tokenOut)
    internal
    view
    returns (uint256 priceIn, uint256 priceOut, uint256 ratio)
  {
    priceIn = config.oracleIn.getPrice();
    priceOut = config.oracleOut.getPrice();
    ratio = _toRawRatio(priceIn * priceOut, tokenIn, tokenOut);
  }

  /**
   * @notice Returns the oracle price (1e18), reverting if the adapter price is outside `priceLimits`.
   * @dev Empty oracle slots return identity price 1e18.
   */
  function getPrice(TokenOracle calldata oracle) internal view returns (uint256 price) {
    if (oracle.isEmpty()) return PRECISION;

    (bool inverse, address adapter) = oracle.adapter.unpack();
    price = IOracleAdapter(adapter).getPrice(oracle);
    if (price == 0) revert IOracleAdapter.InvalidOraclePrice();

    (uint128 min, uint128 max) = oracle.priceLimits.unpack();
    if (price < min || price > max) {
      revert OraclePriceOutOfRange(price, min, max);
    }

    return inverse ? Math.mulDiv(PRECISION, PRECISION, price) : price;
  }

  /**
   * @dev Converts a whole-token tokenOut/tokenIn ratio (1e36) to the hook's realized-price unit:
   *      amountOut_raw * 1e36 / amountIn_raw.
   */
  function _toRawRatio(uint256 price, address tokenIn, address tokenOut)
    private
    view
    returns (uint256)
  {
    uint8 decimalsIn = _decimals(tokenIn);
    uint8 decimalsOut = _decimals(tokenOut);
    if (decimalsOut >= decimalsIn) {
      return price * (10 ** uint256(decimalsOut - decimalsIn));
    }
    return price / (10 ** uint256(decimalsIn - decimalsOut));
  }

  function _decimals(address token) private view returns (uint8) {
    return TokenHelper.isNative(token) ? 18 : IERC20Metadata(token).decimals();
  }
}
