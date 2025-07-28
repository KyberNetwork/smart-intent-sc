// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './base/BaseIntentValidator.sol';

import 'ks-common-sc/libraries/token/TokenHelper.sol';

import 'src/libraries/ConditionLibrary.sol';
import 'src/libraries/univ4/StateLibrary.sol';
import 'src/validators/base/BaseConditionalValidator.sol';

contract KSLiquidityRemoveUniV4IntentValidator is BaseIntentValidator, BaseConditionalValidator {
  using StateLibrary for IPoolManager;
  using TokenHelper for address;
  using ConditionLibrary for *;

  error InvalidOwner();
  error InvalidLiquidity();
  error InvalidOutputAmount();

  ConditionType public constant UNIV4_YIELD_BASED =
    ConditionType.wrap(keccak256('UNIV4_YIELD_BASED'));

  uint256 public constant PRECISION = 1_000_000;
  uint256 public constant Q96 = 1 << 96;

  /**
   * @notice Local variables for remove liquidity validation
   * @param recipient The recipient of the output tokens
   * @param positionManager The position manager contract
   * @param tokenId The token ID
   * @param outputTokens The tokens received after removing liquidity
   * @param tokenBalanceBefore The token balance before removing liquidity
   * @param maxFeePercent The maximum fee percent for the output tokens compared to the expected amounts (1_000_000 = 100%)
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
    uint256 maxFeePercent;
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
   * @param nodes The nodes of conditions (used to build the condition tree)
   * @param maxFeePercents The maximum fee percents for the output tokens compared to the expected amounts (1_000_000 = 100%)
   * @param recipient The recipient
   */
  struct RemoveLiquidityValidationData {
    address[] nftAddresses;
    uint256[] nftIds;
    address[][] outputTokens;
    Node[][] nodes;
    uint256[] maxFeePercents;
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

    Node[] calldata nodes = _cacheAndDecodeValidationData(coreData.validationData, localVar, index);

    ConditionTree memory conditionTree =
      _buildConditionTree(nodes, fee0Collected, fee1Collected, localVar.sqrtPriceX96);

    this.validateConditionTree(conditionTree, 0);

    uint256 fee0Unclaimed;
    uint256 fee1Unclaimed;
    (localVar.amount0, localVar.amount1, fee0Unclaimed, fee1Unclaimed) = localVar
      .positionManager
      .poolManager().computePositionValues(
      localVar.positionManager, localVar.tokenId, localVar.liquidity
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

  /// @inheritdoc IKSConditionalValidator
  function evaluateCondition(Condition calldata condition, bytes calldata additionalData)
    public
    view
    override
    returns (bool isSatisfied)
  {
    if (condition.isType(UNIV4_YIELD_BASED)) {
      isSatisfied = _evaluateUniV4YieldCondition(condition, additionalData);
    } else {
      isSatisfied = super.evaluateCondition(condition, additionalData);
    }
  }

  function _buildConditionTree(
    Node[] calldata nodes,
    uint256 fee0Collected,
    uint256 fee1Collected,
    uint160 sqrtPriceX96
  ) internal pure returns (ConditionTree memory conditionTree) {
    conditionTree.nodes = nodes;
    conditionTree.additionalData = new bytes[](nodes.length);
    for (uint256 i; i < nodes.length; ++i) {
      if (!nodes[i].isLeaf() || nodes[i].condition.isType(TIME_BASED)) {
        continue;
      }
      if (nodes[i].condition.isType(UNIV4_YIELD_BASED)) {
        conditionTree.additionalData[i] = abi.encode(fee0Collected, fee1Collected, sqrtPriceX96);
      } else if (nodes[i].condition.isType(PRICE_BASED)) {
        conditionTree.additionalData[i] = abi.encode(sqrtPriceX96);
      }
    }
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
        outputAmounts[i] * PRECISION >= amount * (PRECISION - localVar.maxFeePercent),
        InvalidOutputAmount()
      );
    }
  }

  function _cacheAndDecodeValidationData(
    bytes calldata data,
    LocalVar memory localVar,
    uint256 index
  ) internal view returns (Node[] calldata nodes) {
    RemoveLiquidityValidationData calldata validationData = _decodeValidationData(data);
    nodes = validationData.nodes[index];

    localVar.recipient = validationData.recipient;
    localVar.positionManager = IPositionManager(validationData.nftAddresses[index]);
    localVar.tokenId = validationData.nftIds[index];
    localVar.liquidityBefore = localVar.positionManager.getPositionLiquidity(localVar.tokenId);
    localVar.outputTokens = validationData.outputTokens[index];
    localVar.maxFeePercent = validationData.maxFeePercents[index];
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

  /**
   * @notice helper function to evaluate whether the yield condition is satisfied
   * @dev Calculates yield as: (fees_in_token0_terms) / (initial_amounts_in_token0_terms)
   * @param condition The yield condition containing target yield and initial amounts
   * @param additionalData Encoded fee0, fee1, and sqrtPriceX96 values
   * @return true if actual yield >= target yield, false otherwise
   */
  function _evaluateUniV4YieldCondition(Condition calldata condition, bytes calldata additionalData)
    internal
    pure
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
  function _convertToken1ToToken0(uint160 sqrtPriceX96, uint256 amount1)
    internal
    pure
    returns (uint256 amount0)
  {
    amount0 = Math.mulDiv(Math.mulDiv(amount1, Q96, sqrtPriceX96), Q96, sqrtPriceX96);
  }
}
