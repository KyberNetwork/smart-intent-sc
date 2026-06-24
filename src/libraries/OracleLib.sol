// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IERC20Metadata} from 'openzeppelin-contracts/contracts/interfaces/IERC20Metadata.sol';
import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';

import {AggregatorV3Interface} from '../interfaces/oracle/external/AggregatorV3Interface.sol';
import {IPyth} from '../interfaces/oracle/external/IPyth.sol';
import {PackedU128, PackedU128Library} from '../types/PackedU128.sol';

library OracleLib {
  uint256 internal constant PRECISION = 1e18;

  enum OracleType {
    NONE,
    CHAINLINK,
    PYTH
  }

  /**
   * @notice Oracle for a single token.
   * @param oracleType type of the oracle.
   * @param source Chainlink: token/USD feed; Pyth: IPyth contract. Zero = no oracle for this leg.
   * @param priceId Pyth price id (unused for Chainlink).
   * @param priceLimits USD price band, USD-per-whole-token 1e18 (min 128bits | max 128bits).
   */
  struct TokenOracle {
    OracleType oracleType;
    address source;
    bytes32 priceId;
    PackedU128 priceLimits;
  }

  /**
   * @param oracleIn Input-token oracle.
   * @param oracleOut Output-token oracle.
   * @param oracleParams maxStaleness 128bits | maxDeviation 128bits, scaled by 1e18 (0 disables slippage guard).
   */
  struct OracleConfig {
    TokenOracle oracleIn;
    TokenOracle oracleOut;
    PackedU128 oracleParams;
  }

  error InvalidOraclePrice();
  error InvalidMaxDeviation();
  error StaleOraclePrice();

  /**
   * @notice Validates a swap. Each configured leg's oracle price must sit in its band; an
   *         unconfigured leg is skipped. The slippage guard ensures the realized price does not
   *         fall more than `maxDeviation` below the oracle ratio; better execution is allowed.
   *         It applies only when both legs are set. True if no leg is set.
   * @param realizedPrice Realized swap price, raw basis (`amountOut_raw * 1e18 / amountIn_raw`).
   */
  function validate(
    OracleConfig memory config,
    address tokenIn,
    address tokenOut,
    uint256 realizedPrice
  ) internal view returns (bool) {
    (uint128 maxStaleness, uint128 maxDeviation) = config.oracleParams.unpack();
    require(maxDeviation <= PRECISION, InvalidMaxDeviation());

    bool hasIn = config.oracleIn.source != address(0);
    bool hasOut = config.oracleOut.source != address(0);
    if (!hasIn && !hasOut) return true; // no oracle configured

    uint256 priceIn;
    uint256 priceOut;

    // market-price trigger: only configured legs are read and bounded
    if (hasIn) {
      priceIn = _usdPrice(config.oracleIn, maxStaleness);
      (uint128 minPriceIn, uint128 maxPriceIn) = config.oracleIn.priceLimits.unpack();
      if (priceIn < minPriceIn || priceIn > maxPriceIn) {
        return false;
      }
    }
    if (hasOut) {
      priceOut = _usdPrice(config.oracleOut, maxStaleness);
      (uint128 minPriceOut, uint128 maxPriceOut) = config.oracleOut.priceLimits.unpack();
      if (priceOut < minPriceOut || priceOut > maxPriceOut) {
        return false;
      }
    }

    // slippage guard: needs both legs to derive the ratio
    if (maxDeviation != 0 && hasIn && hasOut) {
      uint256 ratio = _ratio(priceIn, priceOut, tokenIn, tokenOut);
      if (maxDeviation < PRECISION) {
        uint256 minRealizedPrice = Math.mulDiv(ratio, PRECISION - maxDeviation, PRECISION);
        if (realizedPrice < minRealizedPrice) return false;
      }
    }

    return true;
  }

  /// @notice Both tokens' USD prices (1e18) and the derived raw-basis ratio. Both legs required.
  function getPrices(OracleConfig memory config, address tokenIn, address tokenOut)
    internal
    view
    returns (uint256 priceIn, uint256 priceOut, uint256 ratio)
  {
    (uint128 maxStaleness,) = config.oracleParams.unpack();
    priceIn = _usdPrice(config.oracleIn, maxStaleness);
    priceOut = _usdPrice(config.oracleOut, maxStaleness);
    ratio = _ratio(priceIn, priceOut, tokenIn, tokenOut);
  }

  /// @dev ratio = (priceIn / priceOut) * 1e18 * 10^(decimalsOut - decimalsIn).
  function _ratio(uint256 priceIn, uint256 priceOut, address tokenIn, address tokenOut)
    private
    view
    returns (uint256)
  {
    uint8 decimalsIn = IERC20Metadata(tokenIn).decimals();
    uint8 decimalsOut = IERC20Metadata(tokenOut).decimals();
    if (decimalsOut >= decimalsIn) {
      return Math.mulDiv(priceIn, PRECISION * (10 ** uint256(decimalsOut - decimalsIn)), priceOut);
    }
    return Math.mulDiv(priceIn, PRECISION, priceOut * (10 ** uint256(decimalsIn - decimalsOut)));
  }

  /// @dev Token oracle price, USD-per-whole-token (1e18).
  function _usdPrice(TokenOracle memory oracle, uint256 maxStaleness)
    private
    view
    returns (uint256)
  {
    if (oracle.oracleType == OracleType.CHAINLINK) {
      (, int256 answer,, uint256 updatedAt,) =
        AggregatorV3Interface(oracle.source).latestRoundData();
      if (answer <= 0) revert InvalidOraclePrice();
      if (block.timestamp - updatedAt > maxStaleness) {
        revert StaleOraclePrice();
      }
      uint8 feedDecimals = AggregatorV3Interface(oracle.source).decimals();
      return Math.mulDiv(uint256(answer), PRECISION, 10 ** feedDecimals);
    }

    // PYTH: price = pyth.price * 10^(expo + 18)
    IPyth.Price memory price =
      IPyth(oracle.source).getPriceNoOlderThan(oracle.priceId, maxStaleness);
    if (price.price <= 0) revert InvalidOraclePrice();

    int256 exponent = int256(price.expo) + 18;
    if (exponent >= 0) {
      return uint256(uint64(price.price)) * (10 ** uint256(exponent));
    }
    return uint256(uint64(price.price)) / (10 ** uint256(-exponent));
  }
}
