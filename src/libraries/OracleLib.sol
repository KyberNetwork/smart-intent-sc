// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IERC20Metadata} from 'openzeppelin-contracts/contracts/interfaces/IERC20Metadata.sol';
import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';

import {AggregatorV3Interface} from '../interfaces/oracle/external/AggregatorV3Interface.sol';
import {IPyth} from '../interfaces/oracle/external/IPyth.sol';

library OracleLib {
  uint256 internal constant PRICE_PRECISION = 1e18;
  uint256 internal constant BPS_DENOMINATOR = 10_000;

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
    uint256 priceLimits;
  }

  /**
   * @param oracleIn Input-token oracle.
   * @param oracleOut Output-token oracle.
   * @param oracleParams maxStaleness 128bits | maxDeviationBps 128bits (0 disables slippage guard).
   */
  struct OracleConfig {
    TokenOracle oracleIn;
    TokenOracle oracleOut;
    uint256 oracleParams;
  }

  error InvalidOraclePrice();
  error StaleOraclePrice();

  /**
   * @notice Pushes the Pyth update
   */
  function refresh(OracleConfig memory config, bytes[] calldata updateData) internal {
    if (updateData.length == 0) return;
    address pythIn =
      config.oracleIn.oracleType == OracleType.PYTH ? config.oracleIn.source : address(0);
    address pythOut =
      config.oracleOut.oracleType == OracleType.PYTH ? config.oracleOut.source : address(0);
    if (pythIn != address(0)) {
      _pythUpdate(pythIn, updateData);
    }
    if (pythOut != address(0) && pythOut != pythIn) {
      _pythUpdate(pythOut, updateData);
    }
  }

  /**
   * @notice Validates a swap. Each configured leg's oracle price must sit in its band; an
   *         unconfigured leg is skipped. The slippage guard (realized within `maxDeviationBps` of
   *         the oracle ratio) applies only when both legs are set. True if no leg is set.
   * @param realizedPrice Realized swap price, raw basis (`amountOut_raw * 1e18 / amountIn_raw`).
   */
  function validate(
    OracleConfig memory config,
    address tokenIn,
    address tokenOut,
    uint256 realizedPrice
  ) internal view returns (bool) {
    bool hasIn = config.oracleIn.source != address(0);
    bool hasOut = config.oracleOut.source != address(0);
    if (!hasIn && !hasOut) return true; // no oracle configured

    uint256 maxStaleness = config.oracleParams >> 128;
    uint256 priceIn;
    uint256 priceOut;

    // market-price trigger: only configured legs are read and bounded
    if (hasIn) {
      priceIn = _usdPrice(config.oracleIn, maxStaleness);
      if (
        priceIn < config.oracleIn.priceLimits >> 128
          || priceIn > uint128(config.oracleIn.priceLimits)
      ) {
        return false;
      }
    }
    if (hasOut) {
      priceOut = _usdPrice(config.oracleOut, maxStaleness);
      if (
        priceOut < config.oracleOut.priceLimits >> 128
          || priceOut > uint128(config.oracleOut.priceLimits)
      ) {
        return false;
      }
    }

    // slippage guard: needs both legs to derive the ratio
    uint256 maxDeviationBps = uint128(config.oracleParams);
    if (maxDeviationBps != 0 && hasIn && hasOut) {
      uint256 ratio = _ratio(priceIn, priceOut, tokenIn, tokenOut);
      uint256 diff = realizedPrice > ratio ? realizedPrice - ratio : ratio - realizedPrice;
      if (diff * BPS_DENOMINATOR > maxDeviationBps * ratio) return false;
    }

    return true;
  }

  /// @notice Both tokens' USD prices (1e18) and the derived raw-basis ratio. Both legs required.
  function getPrices(OracleConfig memory config, address tokenIn, address tokenOut)
    internal
    view
    returns (uint256 priceIn, uint256 priceOut, uint256 ratio)
  {
    uint256 maxStaleness = config.oracleParams >> 128;
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
      return
        Math.mulDiv(priceIn, PRICE_PRECISION * (10 ** uint256(decimalsOut - decimalsIn)), priceOut);
    }
    return
      Math.mulDiv(priceIn, PRICE_PRECISION, priceOut * (10 ** uint256(decimalsIn - decimalsOut)));
  }

  function _pythUpdate(address pyth, bytes[] calldata updateData) private {
    IPyth(pyth).updatePriceFeeds{value: IPyth(pyth).getUpdateFee(updateData)}(updateData);
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
      if (maxStaleness != 0 && block.timestamp - updatedAt > maxStaleness) {
        revert StaleOraclePrice();
      }
      uint8 feedDecimals = AggregatorV3Interface(oracle.source).decimals();
      return Math.mulDiv(uint256(answer), PRICE_PRECISION, 10 ** feedDecimals);
    }

    // PYTH: price = pyth.price * 10^(expo + 18)
    uint256 age = maxStaleness == 0 ? type(uint256).max : maxStaleness;
    IPyth.Price memory price = IPyth(oracle.source).getPriceNoOlderThan(oracle.priceId, age);
    if (price.price <= 0) revert InvalidOraclePrice();

    int256 exponent = int256(price.expo) + 18;
    if (exponent >= 0) {
      return uint256(uint64(price.price)) * (10 ** uint256(exponent));
    }
    return uint256(uint64(price.price)) / (10 ** uint256(-exponent));
  }
}
