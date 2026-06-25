// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IERC20Metadata} from 'openzeppelin-contracts/contracts/interfaces/IERC20Metadata.sol';
import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';

import {AggregatorV3Interface} from '../interfaces/oracle/external/AggregatorV3Interface.sol';
import {IPyth} from '../interfaces/oracle/external/IPyth.sol';
import {PackedU128, PackedU128Library} from '../types/PackedU128.sol';

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
 * @param source Chainlink feed or Pyth contract. Zero = no oracle for this slot.
 * @param priceId Pyth price id (unused for Chainlink).
 * @param priceLimits Normalized price band per whole base token, 1e18-scaled (min 128bits | max 128bits).
 * @param inverse True if the raw oracle price is the inverse of the expected price.
 */
struct TokenOracle {
  OracleType oracleType;
  address source;
  bytes32 priceId;
  PackedU128 priceLimits;
  bool inverse;
}

/**
 * @param oracleIn First price edge.
 * @param oracleOut Second price edge.
 * @param oracleParams maxStaleness 128bits | maxDeviation 128bits, scaled by 1e18 (0 disables slippage guard).
 */
struct OracleConfig {
  TokenOracle oracleIn;
  TokenOracle oracleOut;
  PackedU128 oracleParams;
}

library OracleLib {
  uint256 internal constant PRECISION = 1e18;
  error InvalidOraclePrice();
  error InvalidMaxDeviation();
  error StaleOraclePrice();

  /**
   * @notice Validates oracle price bands and minimum realized swap price.
   * @param realizedPrice Raw swap price: `amountOut_raw * 1e18 / amountIn_raw`.
   */
  function validate(
    OracleConfig calldata config,
    address tokenIn,
    address tokenOut,
    uint256 realizedPrice
  ) internal view returns (bool) {
    (uint128 maxStaleness, uint128 maxDeviation) = config.oracleParams.unpack();
    require(maxDeviation <= PRECISION, InvalidMaxDeviation());

    (uint256 priceIn, bool validIn) = config.oracleIn.getPriceAndValidate(maxStaleness);
    if (!validIn) return false;
    (uint256 priceOut, bool validOut) = config.oracleOut.getPriceAndValidate(maxStaleness);
    if (!validOut) return false;

    if (maxDeviation != 0 && maxDeviation < PRECISION) {
      uint256 ratio = _toRawRatio(Math.mulDiv(priceIn, priceOut, PRECISION), tokenIn, tokenOut);
      uint256 minRealizedPrice = Math.mulDiv(ratio, PRECISION - maxDeviation, PRECISION);
      if (realizedPrice < minRealizedPrice) return false;
    }

    return true;
  }

  /// @notice Returns the oracle price and whether it is inside its configured band.
  /// @dev Empty oracle slots return identity price 1e18 and are always valid.
  function getPriceAndValidate(TokenOracle calldata oracle, uint256 maxStaleness)
    internal
    view
    returns (uint256 price, bool)
  {
    if (oracle.source == address(0)) return (PRECISION, true);
    price = oracle.getPrice(maxStaleness);
    (uint128 min, uint128 max) = oracle.priceLimits.unpack();
    if (price < min || price > max) {
      return (price, false);
    }
    return (price, true);
  }

  /// @notice Oracle edge prices (1e18) and the derived raw-basis ratio.
  function getPrices(OracleConfig calldata config, address tokenIn, address tokenOut)
    internal
    view
    returns (uint256 priceIn, uint256 priceOut, uint256 ratio)
  {
    (uint128 maxStaleness,) = config.oracleParams.unpack();
    priceIn =
      config.oracleIn.source == address(0) ? PRECISION : config.oracleIn.getPrice(maxStaleness);
    priceOut =
      config.oracleOut.source == address(0) ? PRECISION : config.oracleOut.getPrice(maxStaleness);
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
    if (oracle.oracleType == OracleType.CHAINLINK) {
      (, int256 answer,, uint256 updatedAt,) =
        AggregatorV3Interface(oracle.source).latestRoundData();
      if (answer <= 0) revert InvalidOraclePrice();
      if (block.timestamp - updatedAt > maxStaleness) {
        revert StaleOraclePrice();
      }
      uint8 feedDecimals = AggregatorV3Interface(oracle.source).decimals();
      price = Math.mulDiv(uint256(answer), PRECISION, 10 ** feedDecimals);
    } else if (oracle.oracleType == OracleType.PYTH) {
      IPyth.Price memory pythPrice =
        IPyth(oracle.source).getPriceNoOlderThan(oracle.priceId, maxStaleness);
      if (pythPrice.price <= 0) revert InvalidOraclePrice();

      int256 exponent = int256(pythPrice.expo) + 18;
      if (exponent >= 0) {
        price = uint256(uint64(pythPrice.price)) * (10 ** uint256(exponent));
      } else {
        price = uint256(uint64(pythPrice.price)) / (10 ** uint256(-exponent));
      }
    } else {
      revert InvalidOraclePrice();
    }

    if (oracle.inverse) {
      return Math.mulDiv(PRECISION, PRECISION, price);
    }
    return price;
  }
}
