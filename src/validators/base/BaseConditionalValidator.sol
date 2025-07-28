// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../../interfaces/IKSConditionalValidator.sol';
import '../../libraries/ConditionLibrary.sol';

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

abstract contract BaseConditionalValidator is IKSConditionalValidator {
  using ConditionLibrary for *;

  error WrongConditionType();

  ConditionType public constant PRICE_BASED = ConditionType.wrap(keccak256('PRICE_BASED'));
  ConditionType public constant TIME_BASED = ConditionType.wrap(keccak256('TIME_BASED'));

  /// @inheritdoc IKSConditionalValidator
  function validateConditionTree(ConditionTree calldata tree, uint256 curIndex)
    external
    view
    virtual
  {
    require(
      ConditionLibrary.evaluateConditionTree(tree, curIndex, evaluateCondition), ConditionsNotMet()
    );
  }

  /// @inheritdoc IKSConditionalValidator
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
    } else {
      revert WrongConditionType();
    }
  }

  /**
   * @notice helper function to evaluate time condition
   * @param condition the condition to evaluate
   * @return true if the condition is satisfied, false otherwise
   */
  function _evaluateTimeCondition(Condition calldata condition) internal view returns (bool) {
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
    returns (bool)
  {
    PriceCondition calldata priceCondition = _decodePriceCondition(condition.data);

    uint256 currentPrice;
    assembly ("memory-safe") {
      currentPrice := calldataload(additionalData.offset)
    }

    return priceCondition.minPrice <= currentPrice && priceCondition.maxPrice >= currentPrice;
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
