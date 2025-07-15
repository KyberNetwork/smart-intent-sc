// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './base/BaseIntentValidator.sol';

import 'openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol';
import 'src/interfaces/uniswapv4/IPositionManager.sol';
import {FullMath} from 'src/libraries/FullMath.sol';
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
  uint256 public constant MAX_TIME_DIFFERENCE = 60; // 1 minute
  uint256 public constant Q192 = 1 << 192;

  enum ConditionType {
    TIME_BASED,
    YIELD_BASED,
    PRICE_BASED
  }

  enum LogicOperator {
    AND,
    OR
  }

  enum TimeCondition {
    NO_CONDITION,
    BEFORE,
    AT,
    AFTER
  }

  struct Condition {
    ConditionType conditionType;
    bool isActive;
    bytes conditionData;
  }

  struct TimeBasedCondition {
    TimeCondition timeType;
    uint256 targetTimestamp;
  }

  struct YieldBasedCondition {
    uint256 targetYieldBps; // Basis points (10000 = 100%)
    uint256 initialAmounts; // [token0, token1]
    uint256 initialFees; // [fee0, fee1]
  }

  struct PriceBasedCondition {
    uint160 minSqrtPrice;
    uint160 maxSqrtPrice;
  }

  struct ConditionData {
    Condition condition1;
    Condition condition2;
    LogicOperator logicOperator;
  }

  struct ZapOutUniswapV4ValidationData {
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
    (uint256 index, uint256 feesCollected) =
      abi.decode(actionData.validatorData, (uint256, uint256));

    ZapOutUniswapV4ValidationData memory validationData =
      abi.decode(coreData.validationData, (ZapOutUniswapV4ValidationData));

    IPositionManager positionManager = IPositionManager(validationData.nftAddresses[index]);
    uint256 tokenId = validationData.nftIds[index];
    address[] memory outputTokens = validationData.outputTokens[index];
    uint256[] memory minAmountsOut = validationData.minAmountsOut[index];
    ConditionData memory condition = validationData.conditions[index];

    require(
      outputTokens[0] != outputTokens[1] && outputTokens[0] < outputTokens[1]
        && outputTokens.length == OUTPUT_TOKENS && outputTokens.length == minAmountsOut.length,
      InvalidOutputToken()
    );

    IKSSessionIntentRouter.ERC721Data[] calldata erc721Data = actionData.tokenData.erc721Data;
    require(erc721Data[0].token == address(positionManager), InvalidTokenData());
    require(erc721Data[0].tokenId == tokenId, InvalidTokenData());

    uint256[] memory unclaimedFees = new uint256[](2);
    uint160 sqrtPriceX96;
    {
      IPoolManager poolManager = positionManager.poolManager();

      (PoolKey memory poolKey, uint256 positionInfo) =
        positionManager.getPoolAndPositionInfo(tokenId);
      bytes32 poolId = _getPoolId(poolKey);
      int24 tickCurrent;
      (sqrtPriceX96, tickCurrent,,) = poolManager.getSlot0(poolId);
      (int24 tickLower, int24 tickUpper) = _getTickRange(positionInfo);

      (unclaimedFees[0], unclaimedFees[1]) = _computeUnclaimedFees(
        poolManager,
        address(positionManager),
        poolId,
        tickLower,
        tickUpper,
        tickCurrent,
        bytes32(tokenId)
      );
    }

    require(
      _validateConditions(condition, feesCollected, unclaimedFees, outputTokens, sqrtPriceX96),
      ConditionsNotMet()
    );

    uint256 liquidityBefore = positionManager.getPositionLiquidity(tokenId);
    require(liquidityBefore > 0, InvalidLiquidity());
    uint256[] memory tokenBalanceBefore = new uint256[](outputTokens.length);
    for (uint256 i = 0; i < outputTokens.length; i++) {
      tokenBalanceBefore[i] = outputTokens[i].balanceOf(validationData.recipient);
    }

    return abi.encode(
      positionManager,
      tokenId,
      outputTokens,
      liquidityBefore,
      tokenBalanceBefore,
      minAmountsOut,
      validationData.recipient
    );
  }

  /// @inheritdoc IKSSessionIntentValidator
  function validateAfterExecution(
    bytes32,
    IKSSessionIntentRouter.IntentCoreData calldata coreData,
    bytes calldata beforeExecutionData,
    bytes calldata
  ) external view override {
    (
      IPositionManager positionManager,
      uint256 tokenId,
      address[] memory outputTokens,
      uint256 liquidityBefore,
      uint256[] memory tokenBalanceBefore,
      uint256[] memory minAmountsOut,
      address recipient
    ) = abi.decode(
      beforeExecutionData,
      (IPositionManager, uint256, address[], uint256, uint256[], uint256[], address)
    );

    uint256 liquidityAfter = positionManager.getPositionLiquidity(tokenId);
    require(
      liquidityAfter == 0 || positionManager.ownerOf(tokenId) == coreData.mainAddress,
      InvalidOwner()
    );
    uint256 liquidityRemoved = liquidityBefore - liquidityAfter;
    require(liquidityRemoved > 0, InvalidLiquidity());

    uint256[] memory outputAmounts = new uint256[](outputTokens.length);
    for (uint256 i = 0; i < outputTokens.length; i++) {
      outputAmounts[i] = outputTokens[i].balanceOf(recipient) - tokenBalanceBefore[i];
    }

    _validateOutputAmounts(outputAmounts, minAmountsOut);
  }

  function _validateConditions(
    ConditionData memory condition,
    uint256 feesCollected,
    uint256[] memory unclaimedFees,
    address[] memory outputTokens,
    uint160 sqrtPriceX96
  ) internal view returns (bool) {
    bool condition1Met;
    bool condition2Met;

    if (condition.condition1.isActive) {
      condition1Met = _evaluateCondition(
        condition.condition1, feesCollected, unclaimedFees, outputTokens, sqrtPriceX96
      );
    }

    if (condition.condition2.isActive) {
      condition2Met = _evaluateCondition(
        condition.condition2, feesCollected, unclaimedFees, outputTokens, sqrtPriceX96
      );
    }

    if (condition.logicOperator == LogicOperator.AND) {
      return condition1Met && condition2Met;
    } else if (condition.logicOperator == LogicOperator.OR) {
      return condition1Met || condition2Met;
    }

    return false;
  }

  function _evaluateCondition(
    Condition memory condition,
    uint256 feesCollected,
    uint256[] memory unclaimedFees,
    address[] memory outputTokens,
    uint160 sqrtPriceX96
  ) internal view returns (bool) {
    if (condition.conditionType == ConditionType.TIME_BASED) {
      return _evaluateTimeCondition(condition.conditionData);
    } else if (condition.conditionType == ConditionType.YIELD_BASED) {
      return _evaluateYieldCondition(
        condition.conditionData, feesCollected, unclaimedFees, outputTokens, sqrtPriceX96
      );
    } else if (condition.conditionType == ConditionType.PRICE_BASED) {
      return _evaluatePriceCondition(condition.conditionData, sqrtPriceX96);
    }
    return false;
  }

  function _evaluateTimeCondition(bytes memory conditionData) internal view returns (bool) {
    TimeBasedCondition memory timeCondition = abi.decode(conditionData, (TimeBasedCondition));

    if (timeCondition.timeType == TimeCondition.NO_CONDITION) {
      return true;
    } else if (timeCondition.timeType == TimeCondition.BEFORE) {
      return block.timestamp < timeCondition.targetTimestamp;
    } else if (timeCondition.timeType == TimeCondition.AT) {
      return abs(block.timestamp, timeCondition.targetTimestamp) <= MAX_TIME_DIFFERENCE;
    } else if (timeCondition.timeType == TimeCondition.AFTER) {
      return block.timestamp > timeCondition.targetTimestamp;
    }
    return false;
  }

  function _evaluateYieldCondition(
    bytes memory conditionData,
    uint256 feesCollected,
    uint256[] memory fees,
    address[] memory outputTokens,
    uint160 sqrtPriceX96
  ) internal view returns (bool) {
    YieldBasedCondition memory yieldCondition = abi.decode(conditionData, (YieldBasedCondition));
    uint8 decimals0 = IERC20Metadata(outputTokens[0]).decimals();
    uint8 decimals1 = IERC20Metadata(outputTokens[1]).decimals();
    {
      uint256 fee0Collected = feesCollected >> 128;
      uint256 fee1Collected = uint256(uint128(feesCollected));
      uint256 initialFee0 = yieldCondition.initialFees >> 128;
      uint256 initialFee1 = uint256(uint128(yieldCondition.initialFees));

      fees[0] = _scaleTo18Decimals(fees[0] + fee0Collected - initialFee0, decimals0);
      fees[1] = _scaleTo18Decimals(fees[1] + fee1Collected - initialFee1, decimals1);
    }

    uint256 initialAmount0 = _scaleTo18Decimals(yieldCondition.initialAmounts >> 128, decimals0);
    uint256 initialAmount1 =
      _scaleTo18Decimals(uint256(uint128(yieldCondition.initialAmounts)), decimals1);

    uint256 numerator = fees[0] + _convertToken1ToToken0(sqrtPriceX96, fees[1]);
    uint256 denominator = initialAmount0 + _convertToken1ToToken0(sqrtPriceX96, initialAmount1);
    uint256 yieldBps = (numerator * YIELD_BPS) / denominator;

    if (denominator == 0) return false;

    return yieldBps >= yieldCondition.targetYieldBps;
  }

  function _evaluatePriceCondition(bytes memory conditionData, uint160 sqrtPriceX96)
    internal
    pure
    returns (bool)
  {
    PriceBasedCondition memory priceCondition = abi.decode(conditionData, (PriceBasedCondition));

    return
      sqrtPriceX96 >= priceCondition.minSqrtPrice && sqrtPriceX96 <= priceCondition.maxSqrtPrice;
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

  function _getTickRange(uint256 posInfo)
    internal
    pure
    returns (int24 _tickLower, int24 _tickUpper)
  {
    assembly {
      _tickLower := signextend(2, shr(8, posInfo))
      _tickUpper := signextend(2, shr(32, posInfo))
    }
  }

  function _convertToken1ToToken0(uint256 sqrtPriceX96, uint256 amount1)
    internal
    pure
    returns (uint256 amount0)
  {
    require(sqrtPriceX96 > 0, 'sqrtPriceX96 must be > 0');

    // Calculate (sqrtPriceX96)^2
    uint256 sqrtPriceX96Squared = sqrtPriceX96 * sqrtPriceX96;

    // amount0 = amount1 * Q192 / sqrtPriceX96Squared
    amount0 = (amount1 * Q192) / sqrtPriceX96Squared;
  }

  function _scaleTo18Decimals(uint256 amount, uint8 decimals) internal pure returns (uint256) {
    if (decimals == 18) {
      return amount;
    } else if (decimals < 18) {
      return amount * (10 ** (18 - decimals));
    } else {
      return amount / (10 ** (decimals - 18));
    }
  }

  function _computeUnclaimedFees(
    IPoolManager poolManager,
    address owner,
    bytes32 poolId,
    int24 tickCurrent,
    int24 tickLower,
    int24 tickUpper,
    bytes32 salt
  ) internal view returns (uint256 feesOwed0, uint256 feesOwed1) {
    bytes32 positionKey = StateLibrary.calculatePositionKey(owner, tickLower, tickUpper, salt);

    (uint128 liquidity, uint256 feeGrowthInside0Last, uint256 feeGrowthInside1Last) =
      poolManager.getPositionInfo(poolId, positionKey);
    uint256 Q128 = 1 << 128;

    (uint256 feeGrowthInside0, uint256 feeGrowthInside1) =
      _getFeeGrowthInside(poolManager, poolId, tickLower, tickUpper, tickCurrent);

    unchecked {
      feesOwed0 = FullMath.mulDivFloor(feeGrowthInside0 - feeGrowthInside0Last, liquidity, Q128);
      feesOwed1 = FullMath.mulDivFloor(feeGrowthInside1 - feeGrowthInside1Last, liquidity, Q128);
    }
  }

  function _getFeeGrowthInside(
    IPoolManager poolManager,
    bytes32 poolId,
    int24 tickLower,
    int24 tickUpper,
    int24 tickCurrent
  ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
    (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) =
      poolManager.getFeeGrowthGlobals(poolId);
    (uint256 feeGrowthOutside0X128Lower, uint256 feeGrowthOutside1X128Lower) =
      poolManager.getTickFeeGrowthOutside(poolId, tickLower);
    (uint256 feeGrowthOutside0X128Upper, uint256 feeGrowthOutside1X128Upper) =
      poolManager.getTickFeeGrowthOutside(poolId, tickUpper);

    uint256 feeGrowthBelow0X128;
    uint256 feeGrowthBelow1X128;
    unchecked {
      if (tickCurrent >= tickLower) {
        feeGrowthBelow0X128 = feeGrowthOutside0X128Lower;
        feeGrowthBelow1X128 = feeGrowthOutside1X128Lower;
      } else {
        feeGrowthBelow0X128 = feeGrowthGlobal0X128 - feeGrowthOutside0X128Lower;
        feeGrowthBelow1X128 = feeGrowthGlobal1X128 - feeGrowthOutside1X128Lower;
      }

      uint256 feeGrowthAbove0X128;
      uint256 feeGrowthAbove1X128;
      if (tickCurrent < tickUpper) {
        feeGrowthAbove0X128 = feeGrowthOutside0X128Upper;
        feeGrowthAbove1X128 = feeGrowthOutside1X128Upper;
      } else {
        feeGrowthAbove0X128 = feeGrowthGlobal0X128 - feeGrowthOutside0X128Upper;
        feeGrowthAbove1X128 = feeGrowthGlobal1X128 - feeGrowthOutside1X128Upper;
      }

      feeGrowthInside0X128 = feeGrowthGlobal0X128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;
      feeGrowthInside1X128 = feeGrowthGlobal1X128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;
    }
  }

  function _sqrtPriceX96ToPrice(uint160 sqrtPriceX96) internal pure returns (uint256) {
    return (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) >> 192;
  }

  function abs(uint256 a, uint256 b) internal pure returns (uint256) {
    return a >= b ? a - b : b - a;
  }
}
