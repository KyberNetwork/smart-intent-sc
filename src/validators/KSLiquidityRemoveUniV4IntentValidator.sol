// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './base/BaseIntentValidator.sol';
import 'src/interfaces/uniswapv4/IPositionManager.sol';

import {Math} from '@openzeppelin-contracts/utils/math/Math.sol';
import 'src/libraries/StateLibrary.sol';
import 'src/libraries/TokenLibrary.sol';

contract KSLiquidityRemoveUniV4IntentValidator is BaseIntentValidator {
  using StateLibrary for IPoolManager;
  using TokenLibrary for address;

  error InvalidZapOutPosition();
  error OutsidePriceRange(uint160 sqrtPLower, uint160 sqrtPUpper, uint160 sqrtPriceX96);
  error InvalidOwner();
  error InvalidOutputToken();
  error InvalidOutputAmounts();
  error ConditionsNotMet();
  error LengthMismatch();
  error InvalidLiquidity();

  uint256 public constant OUTPUT_TOKENS = 2;
  uint256 public constant YIELD_BPS = 10_000;
  uint256 public constant Q192 = 1 << 192;

  // the time condition is already validated in the router
  enum ConditionType {
    YIELD_BASED,
    PRICE_BASED
  }

  struct Condition {
    ConditionType conditionType;
    bytes conditionData;
  }

  struct YieldBasedCondition {
    uint256 targetYieldBps; // Basis points (10000 = 100%)
    uint256 initialAmounts; // [token0, token1]
  }

  struct PriceBasedCondition {
    uint160 minSqrtPrice;
    uint160 maxSqrtPrice;
  }

  /**
   * @dev 2D array for logical expressions represented in Disjunctive Normal Form
   * Example: (A and B) or (C and D and E) = [[A,B], [C,D,E]]
   */
  struct ConditionData {
    Condition[][] conditions;
  }

  struct LocalVar {
    address recipient;
    IPositionManager positionManager;
    uint256 tokenId;
    address[] outputTokens;
    uint256[] minAmountsOut;
    uint256 liquidityBefore;
    uint256[] tokenBalanceBefore;
    uint160 sqrtPriceX96;
  }

  struct RemoveLiquidityValidationData {
    address[] nftAddresses;
    uint256[] nftIds;
    address[][] outputTokens;
    uint256[][] minAmountsOut;
    ConditionData[] conditions;
    address recipient;
  }

  modifier checkTokenLengths(IKSSessionIntentRouter.TokenData calldata tokenData) override {
    require(tokenData.erc20Data.length == 0, InvalidTokenData());
    require(tokenData.erc721Data.length == 1, InvalidTokenData());
    require(tokenData.erc1155Data.length == 0, InvalidTokenData());
    _;
  }

  /// @inheritdoc IKSSessionIntentValidator
  function validateBeforeExecution(
    bytes32,
    IKSSessionIntentRouter.IntentCoreData calldata coreData,
    IKSSessionIntentRouter.ActionData calldata actionData
  )
    external
    view
    override
    checkTokenLengths(actionData.tokenData)
    returns (bytes memory beforeExecutionData)
  {
    (uint256 index, uint256 feesCollected) = _decodeValidatorData(actionData.validatorData);
    // to avoid stack too deep
    LocalVar memory localVar;
    Condition[][] calldata conditions =
      _cacheAndDecodeValidationData(coreData.validationData, localVar, index);
    _validateTokenData(actionData.tokenData, localVar);
    _validateConditions(conditions, feesCollected, localVar.sqrtPriceX96);

    return abi.encode(localVar);
  }

  /// @inheritdoc IKSSessionIntentValidator
  function validateAfterExecution(
    bytes32,
    IKSSessionIntentRouter.IntentCoreData calldata coreData,
    bytes calldata beforeExecutionData,
    bytes calldata
  ) external view override {
    LocalVar calldata localVar = _decodeBeforeExecutionData(beforeExecutionData);

    uint256 liquidityAfter = localVar.positionManager.getPositionLiquidity(localVar.tokenId);
    require(
      localVar.positionManager.ownerOf(localVar.tokenId) == coreData.mainAddress, InvalidOwner()
    );
    require(localVar.liquidityBefore - liquidityAfter > 0, InvalidLiquidity());

    uint256[] memory outputAmounts = new uint256[](localVar.outputTokens.length);
    for (uint256 i; i < localVar.outputTokens.length; ++i) {
      outputAmounts[i] =
        localVar.outputTokens[i].balanceOf(localVar.recipient) - localVar.tokenBalanceBefore[i];
    }
    _validateOutputAmounts(outputAmounts, localVar.minAmountsOut);
  }

  function _validateTokenData(
    IKSSessionIntentRouter.TokenData calldata tokenData,
    LocalVar memory localVar
  ) internal view {
    require(tokenData.erc20Data.length == 0, InvalidTokenData());
    require(tokenData.erc721Data.length == 1, InvalidTokenData());
    require(
      localVar.outputTokens[0] != localVar.outputTokens[1]
        && localVar.outputTokens.length == OUTPUT_TOKENS
        && localVar.outputTokens.length == localVar.minAmountsOut.length,
      InvalidOutputToken()
    );
    require(localVar.liquidityBefore > 0, InvalidLiquidity());
  }

  function _validateConditions(
    Condition[][] calldata conditions,
    uint256 feesCollected,
    uint160 sqrtPriceX96
  ) internal pure {
    if (conditions.length == 0) return;

    // each condition is a disjunction (or) of conjunctions (and)
    for (uint256 i; i < conditions.length; ++i) {
      if (_evaluateConjunction(conditions[i], feesCollected, sqrtPriceX96)) {
        return;
      } else {
        // if false, continue to the next condition
        continue;
      }
    }

    revert ConditionsNotMet();
  }

  function _evaluateConjunction(
    Condition[] calldata conjunction,
    uint256 feesCollected,
    uint160 sqrtPriceX96
  ) internal pure returns (bool) {
    if (conjunction.length == 0) return true;

    bool meetCondition;
    for (uint256 i; i < conjunction.length; ++i) {
      if (conjunction[i].conditionType == ConditionType.YIELD_BASED) {
        meetCondition =
          _evaluateYieldCondition(conjunction[i].conditionData, feesCollected, sqrtPriceX96);
      } else if (conjunction[i].conditionType == ConditionType.PRICE_BASED) {
        meetCondition = _evaluatePriceCondition(conjunction[i].conditionData, sqrtPriceX96);
      }
      if (!meetCondition) {
        return false;
      }
    }
    return true;
  }

  function _evaluateYieldCondition(
    bytes calldata conditionData,
    uint256 feesCollected,
    uint160 sqrtPriceX96
  ) internal pure returns (bool) {
    YieldBasedCondition calldata yieldCondition = _decodeYieldCondition(conditionData);

    uint256 fee0Collected = feesCollected >> 128;
    uint256 fee1Collected = uint256(uint128(feesCollected));

    uint256 initialAmount0 = yieldCondition.initialAmounts >> 128;
    uint256 initialAmount1 = uint256(uint128(yieldCondition.initialAmounts));

    uint256 numerator = fee0Collected + _convertToken1ToToken0(sqrtPriceX96, fee1Collected);
    uint256 denominator = initialAmount0 + _convertToken1ToToken0(sqrtPriceX96, initialAmount1);
    if (denominator == 0) return false;

    uint256 yieldBps = (numerator * YIELD_BPS) / denominator;

    return yieldBps >= yieldCondition.targetYieldBps;
  }

  function _evaluatePriceCondition(bytes calldata conditionData, uint160 sqrtPriceX96)
    internal
    pure
    returns (bool)
  {
    PriceBasedCondition calldata priceCondition = _decodePriceCondition(conditionData);

    return priceCondition.minSqrtPrice < priceCondition.maxSqrtPrice
      && sqrtPriceX96 >= priceCondition.minSqrtPrice && sqrtPriceX96 <= priceCondition.maxSqrtPrice;
  }

  function _validateOutputAmounts(uint256[] memory outputAmounts, uint256[] memory minAmountsOut)
    internal
    pure
  {
    require(outputAmounts.length == minAmountsOut.length, LengthMismatch());
    for (uint256 i; i < outputAmounts.length; ++i) {
      require(outputAmounts[i] >= minAmountsOut[i], InvalidOutputAmounts());
    }
  }

  function _getPoolId(PoolKey memory poolKey) internal pure returns (bytes32 poolId) {
    assembly {
      poolId := keccak256(poolKey, 0xa0)
    }
  }

  function _convertToken1ToToken0(uint256 sqrtPriceX96, uint256 amount1)
    internal
    pure
    returns (uint256 amount0)
  {
    // Calculate (sqrtPriceX96)^2
    uint256 sqrtPriceX96Squared = sqrtPriceX96 * sqrtPriceX96;
    // amount0 = amount1 * Q192 / sqrtPriceX96Squared
    amount0 = Math.mulDiv(amount1, Q192, sqrtPriceX96Squared);
  }

  function _decodeValidatorData(bytes calldata data)
    internal
    pure
    returns (uint256 index, uint256 feesCollected)
  {
    assembly ("memory-safe") {
      index := calldataload(data.offset)
      feesCollected := calldataload(add(data.offset, 0x20))
    }
  }

  function _decodePriceCondition(bytes calldata data)
    internal
    pure
    returns (PriceBasedCondition calldata priceCondition)
  {
    assembly ("memory-safe") {
      priceCondition := data.offset
    }
  }

  function _decodeYieldCondition(bytes calldata data)
    internal
    pure
    returns (YieldBasedCondition calldata yieldCondition)
  {
    assembly ("memory-safe") {
      yieldCondition := data.offset
    }
  }

  function _cacheAndDecodeValidationData(
    bytes calldata data,
    LocalVar memory localVar,
    uint256 index
  ) internal view returns (Condition[][] calldata conditions) {
    RemoveLiquidityValidationData calldata validationData;
    assembly ("memory-safe") {
      validationData := add(data.offset, calldataload(data.offset))
    }
    conditions = validationData.conditions[index].conditions;

    localVar.recipient = validationData.recipient;
    localVar.positionManager = IPositionManager(validationData.nftAddresses[index]);
    localVar.tokenId = validationData.nftIds[index];
    localVar.outputTokens = validationData.outputTokens[index];
    localVar.minAmountsOut = validationData.minAmountsOut[index];
    localVar.liquidityBefore = localVar.positionManager.getPositionLiquidity(localVar.tokenId);
    localVar.tokenBalanceBefore = new uint256[](localVar.outputTokens.length);
    for (uint256 i; i < localVar.outputTokens.length; ++i) {
      localVar.tokenBalanceBefore[i] = localVar.outputTokens[i].balanceOf(localVar.recipient);
    }

    {
      IPoolManager poolManager = localVar.positionManager.poolManager();

      (PoolKey memory poolKey,) = localVar.positionManager.getPoolAndPositionInfo(localVar.tokenId);
      bytes32 poolId = _getPoolId(poolKey);
      (localVar.sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
    }
  }

  function _decodeBeforeExecutionData(bytes calldata data)
    internal
    pure
    returns (LocalVar calldata localVar)
  {
    assembly ("memory-safe") {
      localVar := add(data.offset, calldataload(data.offset))
    }
  }
}
