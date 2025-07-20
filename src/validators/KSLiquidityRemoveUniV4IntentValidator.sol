// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './base/BaseIntentValidator.sol';

import 'src/interfaces/IKSConditionBasedValidator.sol';
import 'src/interfaces/uniswapv4/IPositionManager.sol';
import 'src/libraries/ConditionLibrary.sol';
import 'src/libraries/StateLibrary.sol';
import 'src/libraries/TokenLibrary.sol';

contract KSLiquidityRemoveUniV4IntentValidator is BaseIntentValidator, IKSConditionBasedValidator {
  using StateLibrary for IPoolManager;
  using TokenLibrary for address;
  using ConditionLibrary for Condition;

  error InvalidOwner();
  error InvalidOutputToken();
  error LengthMismatch();
  error InvalidLiquidity();
  error BelowMinRate(address outputToken, uint256 liquidity, uint256 minRate, uint256 outputAmount);

  uint256 public constant OUTPUT_TOKENS = 2;
  uint256 public constant RATE_DENOMINATOR = 1e18;

  struct LocalVar {
    address recipient;
    IPositionManager positionManager;
    uint256 tokenId;
    address[] outputTokens;
    uint256[] minRates;
    uint256 liquidityBefore;
    uint256[] tokenBalanceBefore;
    uint160 sqrtPriceX96;
  }

  /**
   * @notice Data structure for remove liquidity validation
   * @param nftAddresses The NFT addresses
   * @param nftIds The NFT IDs
   * @param outputTokens The tokens received after removing liquidity
   * @param minRates The minimum rates, denominated in 1e18 for each token
   * @param dnfExpressions The DNF expressions for conditions
   * @param recipient The recipient
   */
  struct RemoveLiquidityValidationData {
    address[] nftAddresses;
    uint256[] nftIds;
    address[][] outputTokens;
    uint256[][] minRates;
    DNFExpression[] dnfExpressions;
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
    _validateLPData(localVar);
    require(
      _evaluateConditions(conditions, feesCollected, localVar.sqrtPriceX96), ConditionsNotMet()
    );

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
    uint256 liquidity = localVar.liquidityBefore - liquidityAfter;
    require(liquidity > 0, InvalidLiquidity());

    uint256[] memory outputAmounts = new uint256[](localVar.outputTokens.length);
    for (uint256 i; i < localVar.outputTokens.length; ++i) {
      outputAmounts[i] =
        localVar.outputTokens[i].balanceOf(localVar.recipient) - localVar.tokenBalanceBefore[i];
    }
    _validateOutputAmounts(liquidity, localVar.outputTokens, outputAmounts, localVar.minRates);
  }

  /// @inheritdoc IKSConditionBasedValidator
  function validateConditions(DNFExpression calldata dnfExpression, bytes calldata additionalData)
    external
    view
    returns (bool)
  {
    uint256 feesCollected;
    uint160 sqrtPriceX96;
    assembly ("memory-safe") {
      feesCollected := calldataload(additionalData.offset)
      sqrtPriceX96 := calldataload(add(additionalData.offset, 0x20))
    }
    return _evaluateConditions(dnfExpression.conditions, feesCollected, sqrtPriceX96);
  }

  function _validateLPData(LocalVar memory localVar) internal view {
    require(
      localVar.outputTokens[0] != localVar.outputTokens[1]
        && localVar.outputTokens.length <= OUTPUT_TOKENS
        && localVar.outputTokens.length == localVar.minRates.length,
      InvalidOutputToken()
    );
    require(localVar.liquidityBefore > 0, InvalidLiquidity());
  }

  function _evaluateConditions(
    Condition[][] calldata conditions,
    uint256 feesCollected,
    uint160 sqrtPriceX96
  ) internal view returns (bool) {
    if (conditions.length == 0) return true;

    // each condition is a disjunction (or) of conjunctions (and)
    for (uint256 i; i < conditions.length; ++i) {
      if (_evaluateConjunction(conditions[i], feesCollected, sqrtPriceX96)) {
        return true;
      } else {
        // if false, continue to the next condition
        continue;
      }
    }

    return false;
  }

  function _evaluateConjunction(
    Condition[] calldata conjunction,
    uint256 feesCollected,
    uint160 sqrtPriceX96
  ) internal view returns (bool) {
    if (conjunction.length == 0) return true;

    bool meetCondition;
    for (uint256 i; i < conjunction.length; ++i) {
      if (conjunction[i].isType(ConditionLibrary.YIELD_BASED)) {
        meetCondition = conjunction[i].evaluateUniV4YieldCondition(feesCollected, sqrtPriceX96);
      } else if (conjunction[i].isType(ConditionLibrary.PRICE_BASED)) {
        meetCondition = conjunction[i].evaluateUniV4PriceCondition(sqrtPriceX96);
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

  function _validateOutputAmounts(
    uint256 liquidity,
    address[] calldata outputTokens,
    uint256[] memory outputAmounts,
    uint256[] calldata minRates
  ) internal pure {
    require(outputAmounts.length == minRates.length, LengthMismatch());
    for (uint256 i; i < outputAmounts.length; ++i) {
      require(
        outputAmounts[i] * RATE_DENOMINATOR >= minRates[i] * liquidity,
        BelowMinRate(outputTokens[i], liquidity, minRates[i], outputAmounts[i])
      );
    }
  }

  function _getPoolId(PoolKey memory poolKey) internal pure returns (bytes32 poolId) {
    assembly {
      poolId := keccak256(poolKey, 0xa0)
    }
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

  function _cacheAndDecodeValidationData(
    bytes calldata data,
    LocalVar memory localVar,
    uint256 index
  ) internal view returns (Condition[][] calldata conditions) {
    RemoveLiquidityValidationData calldata validationData;
    assembly ("memory-safe") {
      validationData := add(data.offset, calldataload(data.offset))
    }
    conditions = validationData.dnfExpressions[index].conditions;

    localVar.recipient = validationData.recipient;
    localVar.positionManager = IPositionManager(validationData.nftAddresses[index]);
    localVar.tokenId = validationData.nftIds[index];
    localVar.outputTokens = validationData.outputTokens[index];
    localVar.minRates = validationData.minRates[index];
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
