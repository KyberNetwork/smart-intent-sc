// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './base/BaseIntentValidator.sol';

import 'ks-common-sc/libraries/token/TokenHelper.sol';
import 'src/interfaces/IKSConditionBasedValidator.sol';
import 'src/libraries/ConditionLibrary.sol';
import 'src/libraries/univ4/StateLibrary.sol';

contract KSLiquidityRemoveUniV4IntentValidator is BaseIntentValidator, IKSConditionBasedValidator {
  using StateLibrary for IPoolManager;
  using TokenHelper for address;
  using ConditionLibrary for Condition;

  error InvalidOwner();
  error InvalidLiquidity();
  error InvalidOutputAmount();

  /**
   * @notice Local variables for remove liquidity validation
   * @param recipient The recipient of the output tokens
   * @param positionManager The position manager contract
   * @param tokenId The token ID
   * @param outputTokens The tokens received after removing liquidity
   * @param tokenBalanceBefore The token balance before removing liquidity
   * @param minPercentsBps The minimum percents for the output tokens compared to the expected amounts (10000 = 100%)
   * @param liquidity The liquidity to remove
   * @param liquidityBefore The liquidity before removing liquidity
   * @param sqrtPriceX96 The sqrt price X96 of the pool
   * @param amount0 The expected amount of token0 to remove
   * @param amount1 The expected amount of token1 to remove
   */
  struct LocalVar {
    address recipient;
    IPositionManager positionManager;
    uint256 tokenId;
    address[] outputTokens;
    uint256[] tokenBalanceBefore;
    uint256 minPercentsBps;
    uint256 liquidity;
    uint256 liquidityBefore;
    uint160 sqrtPriceX96;
    uint256 amount0;
    uint256 amount1;
  }

  /**
   * @notice Data structure for remove liquidity validation
   * @param nftAddresses The NFT addresses
   * @param nftIds The NFT IDs
   * @param outputTokens The tokens received after removing liquidity
   * @param dnfExpressions The DNF expressions for conditions
   * @param minPercentsBps The minimum percents for the output tokens compared to the expected amounts (10000 = 100%)
   * @param recipient The recipient
   */
  struct RemoveLiquidityValidationData {
    address[] nftAddresses;
    uint256[] nftIds;
    address[][] outputTokens;
    DNFExpression[] dnfExpressions;
    uint256[] minPercentsBps;
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
    // to avoid stack too deep
    LocalVar memory localVar;

    uint256 index;
    uint256 fee0Collected;
    uint256 fee1Collected;
    (index, fee0Collected, fee1Collected, localVar.liquidity) =
      _decodeValidatorData(actionData.validatorData);

    Condition[][] calldata conditions =
      _cacheAndDecodeValidationData(coreData.validationData, localVar, index);

    uint256 fee0Unclaimed;
    uint256 fee1Unclaimed;
    (localVar.amount0, localVar.amount1, fee0Unclaimed, fee1Unclaimed) = localVar
      .positionManager
      .poolManager().computePositionValues(
      localVar.positionManager, localVar.tokenId, localVar.liquidity
    );

    require(
      _evaluateConditions(conditions, fee0Collected, fee1Collected, localVar.sqrtPriceX96),
      ConditionsNotMet()
    );
    localVar.amount0 += fee0Unclaimed;
    localVar.amount1 += fee1Unclaimed;
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
    require(liquidityAfter == localVar.liquidityBefore - localVar.liquidity, InvalidLiquidity());
    require(
      localVar.positionManager.ownerOf(localVar.tokenId) == coreData.mainAddress, InvalidOwner()
    );

    uint256[] memory outputAmounts = new uint256[](localVar.outputTokens.length);
    for (uint256 i; i < localVar.outputTokens.length; ++i) {
      outputAmounts[i] =
        localVar.outputTokens[i].balanceOf(localVar.recipient) - localVar.tokenBalanceBefore[i];
    }
    _validateOutput(localVar, outputAmounts);
  }

  /// @inheritdoc IKSConditionBasedValidator
  function validateConditions(DNFExpression calldata dnfExpression, bytes calldata additionalData)
    external
    view
    returns (bool)
  {
    uint256 fee0;
    uint256 fee1;
    uint160 sqrtPriceX96;

    assembly ("memory-safe") {
      fee0 := calldataload(additionalData.offset)
      fee1 := calldataload(add(additionalData.offset, 0x20))
      sqrtPriceX96 := calldataload(add(additionalData.offset, 0x40))
    }
    return _evaluateConditions(dnfExpression.conditions, fee0, fee1, sqrtPriceX96);
  }

  function _evaluateConditions(
    Condition[][] calldata conditions,
    uint256 fee0,
    uint256 fee1,
    uint160 sqrtPriceX96
  ) internal view returns (bool) {
    if (conditions.length == 0) return true;

    // each condition is a disjunction (or) of conjunctions (and)
    for (uint256 i; i < conditions.length; ++i) {
      if (_evaluateConjunction(conditions[i], fee0, fee1, sqrtPriceX96)) {
        return true;
      }
      // if false, continue to the next condition
    }

    // all conditions are false
    return false;
  }

  function _evaluateConjunction(
    Condition[] calldata conjunction,
    uint256 fee0,
    uint256 fee1,
    uint160 sqrtPriceX96
  ) internal view returns (bool) {
    if (conjunction.length == 0) return true;

    bool meetCondition;
    for (uint256 i; i < conjunction.length; ++i) {
      if (conjunction[i].isType(ConditionLibrary.YIELD_BASED)) {
        meetCondition = conjunction[i].evaluateUniV4YieldCondition(fee0, fee1, sqrtPriceX96);
      } else if (conjunction[i].isType(ConditionLibrary.PRICE_BASED)) {
        meetCondition = conjunction[i].evaluatePriceCondition(sqrtPriceX96);
      } else if (conjunction[i].isType(ConditionLibrary.TIME_BASED)) {
        meetCondition = conjunction[i].evaluateTimeCondition();
      } else {
        revert ConditionLibrary.WrongConditionType();
      }
      if (!meetCondition) {
        return false;
      }
    }
    return true;
  }

  function _validateOutput(LocalVar calldata localVar, uint256[] memory outputAmounts)
    internal
    view
  {
    (PoolKey memory poolKey,) = localVar.positionManager.getPoolAndPositionInfo(localVar.tokenId);
    poolKey.currency0 =
      poolKey.currency0 == address(0) ? TokenHelper.NATIVE_ADDRESS : poolKey.currency0;
    poolKey.currency1 =
      poolKey.currency1 == address(0) ? TokenHelper.NATIVE_ADDRESS : poolKey.currency1;

    for (uint256 i; i < localVar.outputTokens.length; ++i) {
      uint256 amount =
        localVar.outputTokens[i] == poolKey.currency0 ? localVar.amount0 : localVar.amount1;

      require(
        outputAmounts[i] * ConditionLibrary.BPS >= amount * localVar.minPercentsBps,
        InvalidOutputAmount()
      );
    }
  }

  function _cacheAndDecodeValidationData(
    bytes calldata data,
    LocalVar memory localVar,
    uint256 index
  ) internal view returns (Condition[][] calldata conditions) {
    RemoveLiquidityValidationData calldata validationData = _decodeValidationData(data);
    conditions = validationData.dnfExpressions[index].conditions;

    localVar.recipient = validationData.recipient;
    localVar.positionManager = IPositionManager(validationData.nftAddresses[index]);
    localVar.tokenId = validationData.nftIds[index];
    localVar.liquidityBefore = localVar.positionManager.getPositionLiquidity(localVar.tokenId);
    localVar.outputTokens = validationData.outputTokens[index];
    localVar.minPercentsBps = validationData.minPercentsBps[index];
    localVar.tokenBalanceBefore = new uint256[](localVar.outputTokens.length);
    for (uint256 i; i < localVar.outputTokens.length; ++i) {
      localVar.tokenBalanceBefore[i] = localVar.outputTokens[i].balanceOf(localVar.recipient);
    }

    {
      IPoolManager poolManager = localVar.positionManager.poolManager();

      (PoolKey memory poolKey,) = localVar.positionManager.getPoolAndPositionInfo(localVar.tokenId);
      bytes32 poolId = StateLibrary.getPoolId(poolKey);
      (localVar.sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
    }
  }

  function _decodeValidatorData(bytes calldata data)
    internal
    pure
    returns (uint256 index, uint256 fee0Collected, uint256 fee1Collected, uint256 liquidity)
  {
    assembly ("memory-safe") {
      index := calldataload(data.offset)
      fee0Collected := calldataload(add(data.offset, 0x20))
      fee1Collected := calldataload(add(data.offset, 0x40))
      liquidity := calldataload(add(data.offset, 0x60))
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

  function _decodeValidationData(bytes calldata data)
    internal
    pure
    returns (RemoveLiquidityValidationData calldata validationData)
  {
    assembly ("memory-safe") {
      validationData := add(data.offset, calldataload(data.offset))
    }
  }
}
