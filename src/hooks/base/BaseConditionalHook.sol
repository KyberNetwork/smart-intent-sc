// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './BaseHook.sol';
import 'src/interfaces/hooks/IKSConditionalHook.sol';

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

abstract contract BaseConditionalHook is BaseHook, IKSConditionalHook {
  error WrongConditionType();

  ConditionType public constant PRICE_BASED = ConditionType.wrap(keccak256('PRICE_BASED'));
  ConditionType public constant TIME_BASED = ConditionType.wrap(keccak256('TIME_BASED'));
  ConditionType public constant YIELD_BASED = ConditionType.wrap(keccak256('YIELD_BASED'));
  uint256 public constant PRECISION = 1_000_000;
  uint256 public constant Q96 = 1 << 96;

  /// @inheritdoc IKSConditionalHook
  function validateConditionTree(ConditionTree calldata tree, uint256 curIndex)
    external
    view
    virtual
  {
    require(
      ConditionTreeLibrary.evaluateConditionTree(tree, curIndex, evaluateCondition),
      ConditionsNotMet()
    );
  }

  /// @inheritdoc IKSConditionalHook
  function evaluateCondition(Condition calldata condition, bytes calldata additionalData)
    public
    view
    virtual
    returns (bool isSatisfied)
  {
    if (condition.isType(TIME_BASED)) {
      isSatisfied = _evaluateTimeCondition(condition);
    } else if (condition.isType(PRICE_BASED)) {
      isSatisfied = _evaluatePriceCondition(condition, additionalData);
    } else if (condition.isType(YIELD_BASED)) {
      isSatisfied = _evaluateSqrtPriceX96YieldCondition(condition, additionalData);
    } else {
      revert WrongConditionType();
    }
  }

  /**
   * @notice helper function to evaluate time condition
   * @param condition the condition to evaluate
   * @return true if the condition is satisfied, false otherwise
   */
  function _evaluateTimeCondition(Condition calldata condition)
    internal
    view
    virtual
    returns (bool)
  {
    TimeCondition calldata timeCondition = _decodeTimeCondition(condition.data);

    return timeCondition.startTimestamp <= block.timestamp
      && timeCondition.endTimestamp >= block.timestamp;
  }

  /**
   * @notice helper function to evaluate price condition
   * @param condition the price condition to evaluate
   * @param additionalData the abi encoded data of the current price
   * @return true if the condition is satisfied, false otherwise
   */
  function _evaluatePriceCondition(Condition calldata condition, bytes calldata additionalData)
    internal
    pure
    virtual
    returns (bool)
  {
    PriceCondition calldata priceCondition = _decodePriceCondition(condition.data);

    uint256 currentPrice;
    assembly ("memory-safe") {
      currentPrice := calldataload(additionalData.offset)
    }

    return priceCondition.minPrice <= currentPrice && priceCondition.maxPrice >= currentPrice;
  }

  /**
   * @notice helper function to evaluate whether the yield condition (univ3 pool type) is satisfied
   * @dev Calculates yield as: (fees_in_token0_terms) / (initial_amounts_in_token0_terms)
   * @param condition The yield condition containing target yield and initial amounts
   * @param additionalData Encoded fee0, fee1, and sqrtPriceX96 values
   * @return true if actual yield >= target yield, false otherwise
   */
  function _evaluateSqrtPriceX96YieldCondition(
    Condition calldata condition,
    bytes calldata additionalData
  ) internal pure virtual returns (bool) {
    uint256 fee0;
    uint256 fee1;
    uint160 sqrtPriceX96;

    assembly ("memory-safe") {
      fee0 := calldataload(additionalData.offset)
      fee1 := calldataload(add(additionalData.offset, 0x20))
      sqrtPriceX96 := calldataload(add(additionalData.offset, 0x40))
    }

    YieldCondition calldata yieldCondition = _decodeYieldCondition(condition.data);

    uint256 initialAmount0 = yieldCondition.initialAmounts >> 128;
    uint256 initialAmount1 = uint256(uint128(yieldCondition.initialAmounts));

    uint256 numerator = fee0 + _convertToken1ToToken0(sqrtPriceX96, fee1);
    uint256 denominator = initialAmount0 + _convertToken1ToToken0(sqrtPriceX96, initialAmount1);
    if (denominator == 0) return false;

    uint256 yield = (numerator * PRECISION) / denominator;

    return yield >= yieldCondition.targetYield;
  }

  /**
   * @notice Converts token1 amount to equivalent token0 amount using current price
   * @dev formula: amount0 = amount1 * Q192 / sqrtPriceX96^2
   * @param sqrtPriceX96 The pool's sqrt price
   * @param amount1 Amount of token1 to convert
   * @return amount0 Equivalent amount in token0 terms
   */
  function _convertToken1ToToken0(uint256 sqrtPriceX96, uint256 amount1)
    internal
    pure
    virtual
    returns (uint256 amount0)
  {
    amount0 = Math.mulDiv(Math.mulDiv(amount1, Q96, sqrtPriceX96), Q96, sqrtPriceX96);
  }

  function _decodePriceCondition(bytes calldata data)
    internal
    pure
    returns (PriceCondition calldata priceCondition)
  {
    assembly ("memory-safe") {
      priceCondition := data.offset
    }
  }

  function _decodeTimeCondition(bytes calldata data)
    internal
    pure
    returns (TimeCondition calldata timeCondition)
  {
    assembly ("memory-safe") {
      timeCondition := data.offset
    }
  }

  function _decodeYieldCondition(bytes calldata data)
    internal
    pure
    returns (YieldCondition calldata yieldCondition)
  {
    assembly ("memory-safe") {
      yieldCondition := data.offset
    }
  }
}
