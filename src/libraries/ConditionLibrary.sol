// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '@openzeppelin-contracts/utils/math/Math.sol';
import 'src/interfaces/IKSConditionBasedValidator.sol';

using ConditionLibrary for ConditionType;
using ConditionLibrary for IKSConditionBasedValidator.Condition;
using ConditionLibrary for bytes;

/**
 * @param startTimestamp the start timestamp of the condition
 * @param endTimestamp the end timestamp of the condition
 */
struct TimeCondition {
  uint256 startTimestamp;
  uint256 endTimestamp;
}

/**
 * @param targetYield the target yield threshold (1e6 precision)
 * @param initialAmounts the initial amounts of the tokens
 */
struct YieldCondition {
  uint256 targetYield;
  uint256 initialAmounts; // [token0, token1]
}

/**
 * @param minPrice the minimum price of the token (would be in sqrtPriceX96 if uni v3 pool type)
 * @param maxPrice the maximum price of the token (would be in sqrtPriceX96 if uni v3 pool type)
 */
struct PriceCondition {
  uint256 minPrice;
  uint256 maxPrice;
}

library ConditionLibrary {
  error WrongConditionType();

  ConditionType public constant YIELD_BASED = ConditionType.wrap(keccak256('YIELD_BASED'));
  ConditionType public constant PRICE_BASED = ConditionType.wrap(keccak256('PRICE_BASED'));
  ConditionType public constant TIME_BASED = ConditionType.wrap(keccak256('TIME_BASED'));

  uint256 public constant PRECISION = 1_000_000;
  uint256 public constant Q96 = 1 << 96;

  function evaluateTimeCondition(IKSConditionBasedValidator.Condition calldata condition)
    internal
    view
    returns (bool)
  {
    TimeCondition calldata timeCondition = condition.data.decodeTimeCondition();

    return timeCondition.startTimestamp <= block.timestamp
      && timeCondition.endTimestamp >= block.timestamp;
  }

  function evaluateUniV4YieldCondition(
    IKSConditionBasedValidator.Condition calldata condition,
    uint256 fee0,
    uint256 fee1,
    uint160 sqrtPriceX96
  ) internal pure returns (bool) {
    YieldCondition calldata yieldCondition = condition.data.decodeYieldCondition();

    uint256 initialAmount0 = yieldCondition.initialAmounts >> 128;
    uint256 initialAmount1 = uint256(uint128(yieldCondition.initialAmounts));

    uint256 numerator = fee0 + convertToken1ToToken0(sqrtPriceX96, fee1);
    uint256 denominator = initialAmount0 + convertToken1ToToken0(sqrtPriceX96, initialAmount1);
    if (denominator == 0) return false;

    uint256 yield = (numerator * PRECISION) / denominator;

    return yield >= yieldCondition.targetYield;
  }

  function evaluatePriceCondition(
    IKSConditionBasedValidator.Condition calldata condition,
    uint256 price
  ) internal pure returns (bool) {
    PriceCondition calldata priceCondition = condition.data.decodePriceCondition();

    return priceCondition.minPrice <= price && priceCondition.maxPrice >= price;
  }

  function isType(
    IKSConditionBasedValidator.Condition calldata condition,
    ConditionType conditionType
  ) internal pure returns (bool) {
    return ConditionType.unwrap(condition.conditionType) == ConditionType.unwrap(conditionType);
  }

  function decodePriceCondition(bytes calldata data)
    internal
    pure
    returns (PriceCondition calldata priceCondition)
  {
    assembly ("memory-safe") {
      priceCondition := data.offset
    }
  }

  function decodeTimeCondition(bytes calldata data)
    internal
    pure
    returns (TimeCondition calldata timeCondition)
  {
    assembly ("memory-safe") {
      timeCondition := data.offset
    }
  }

  function decodeYieldCondition(bytes calldata data)
    internal
    pure
    returns (YieldCondition calldata yieldCondition)
  {
    assembly ("memory-safe") {
      yieldCondition := data.offset
    }
  }

  function convertToken1ToToken0(uint160 sqrtPriceX96, uint256 amount1)
    internal
    pure
    returns (uint256 amount0)
  {
    amount0 = Math.mulDiv(Math.mulDiv(amount1, Q96, sqrtPriceX96), Q96, sqrtPriceX96);
  }
}
