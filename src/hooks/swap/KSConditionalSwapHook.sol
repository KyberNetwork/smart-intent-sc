// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IKSSmartIntentHook} from '../../interfaces/hooks/IKSSmartIntentHook.sol';
import {OracleConfig, OracleLib} from '../../libraries/OracleLib.sol';
import {ActionData} from '../../types/ActionData.sol';
import {IntentData} from '../../types/IntentData.sol';
import {PackedU128, PackedU128Library} from '../../types/PackedU128.sol';
import {BaseStatefulHook} from '../base/BaseStatefulHook.sol';
import {CalldataDecoder} from 'ks-common-sc/src/libraries/calldata/CalldataDecoder.sol';
import {TokenHelper} from 'ks-common-sc/src/libraries/token/TokenHelper.sol';

contract KSConditionalSwapHook is BaseStatefulHook {
  using TokenHelper for address;
  using CalldataDecoder for bytes;

  error InvalidTokenIn(address tokenIn, address actualTokenIn);
  error AmountInMismatch(uint256 amountIn, uint256 actualAmountIn);
  error InvalidSwap();

  uint256 public constant DENOMINATOR = 1e18;
  uint256 public constant PRECISION = 1_000_000;

  /**
   * @notice Data structure for conditional swap
   * @param swapConditions The swap conditions, a swap will be executed if one of the conditions is met
   * @param srcTokens The source tokens
   * @param dstTokens The destination tokens
   * @param recipient The recipient of the destination token
   */
  struct SwapHookData {
    SwapCondition[][] swapConditions;
    address[] srcTokens;
    address[] dstTokens;
    address recipient;
  }

  /**
   * @notice The limit of swap executions that can be performed for a swap info
   * @param swapLimit The maximum number of times the swap can be executed
   * @param timeLimits The limits of the swap time (minTime 128bits, maxTime 128bits)
   * @param amountInLimits The limits of the swap amount (minAmountIn 128bits, maxAmountIn 128bits)
   * @param maxFees The max fees (srcFee 128bits, dstFee 128bits)
   * @param priceLimits The limits of the realized price (tokenOut/tokenIn denominated by 1e18) (minPrice 128bits, maxPrice 128bits)
   * @param oracle The oracle config, where oracleIn/oracleOut are price edges and an empty edge
   *        is identity price 1, carrying market-price bands and staleness/slippage params
   */
  struct SwapCondition {
    uint8 swapLimit;
    PackedU128 timeLimits;
    PackedU128 amountInLimits;
    PackedU128 maxFees;
    PackedU128 priceLimits;
    OracleConfig oracle;
  }

  struct SwapValidationData {
    bytes32 intentHash;
    uint256 intentIndex;
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
    uint256 recipientBalanceBefore;
    uint256 swapperBalanceBefore;
    uint256 srcFeePercent;
    uint256 dstFeePercent;
    address recipient;
  }

  /**
   * @notice Tracks swap execution counts for each condition to enforce swap limits
   * @dev Maps intentHash -> intentIndex -> packedIndexes -> packedCounts
   *      Each uint256 stores up to 32 uint8 swap counts (8 bits each), indexed by swapIndexes / 32
   *      Individual counts are extracted using bit shifts based on swapIndexes % 32
   */
  mapping(
    bytes32 intentHash
      => mapping(uint256 intentIndex => mapping(uint256 swapIndexes => uint256 swapCount))
  ) public swapRecord;

  constructor(address[] memory initialRouters) BaseStatefulHook(initialRouters) {}

  receive() external payable {}

  modifier checkTokenLengths(ActionData calldata actionData) override {
    require(actionData.erc20Ids.length == 1, InvalidTokenData());
    require(actionData.erc721Ids.length == 0, InvalidTokenData());
    _;
  }

  /// @inheritdoc IKSSmartIntentHook
  function beforeExecution(
    bytes32 intentHash,
    IntentData calldata intentData,
    ActionData calldata actionData
  )
    external
    view
    override
    onlyWhitelistedRouter
    checkTokenLengths(actionData)
    returns (uint256[] memory fees, bytes memory beforeExecutionData)
  {
    (uint256 index, uint256 intentSrcFee, uint256 intentDstFee) =
      _decodeHookActionData(actionData.hookActionData);

    address tokenIn = intentData.tokenData.erc20Data[actionData.erc20Ids[0]].token;
    address tokenOut;
    address recipient;
    // prevent stack too deep
    {
      SwapHookData calldata swapHookData = _decodeHookData(intentData.coreData.hookIntentData);
      tokenOut = swapHookData.dstTokens[index];
      recipient = swapHookData.recipient;

      require(
        tokenIn == swapHookData.srcTokens[index],
        InvalidTokenIn(tokenIn, swapHookData.srcTokens[index])
      );
    }
    uint256 amountIn = actionData.erc20Amounts[0];

    fees = new uint256[](1);
    fees[0] = (amountIn * intentSrcFee) / PRECISION;
    beforeExecutionData = abi.encode(
      intentHash,
      index,
      tokenIn,
      tokenOut,
      amountIn,
      _getRecipientBalance(tokenOut, recipient, intentDstFee),
      tokenIn.balanceOf(intentData.coreData.mainAddress),
      intentSrcFee,
      intentDstFee,
      recipient
    );

    return (fees, beforeExecutionData);
  }

  /// @inheritdoc IKSSmartIntentHook
  function afterExecution(
    bytes32,
    IntentData calldata intentData,
    bytes calldata beforeExecutionData,
    bytes calldata
  )
    external
    override
    onlyWhitelistedRouter
    returns (
      address[] memory tokens,
      uint256[] memory fees,
      uint256[] memory amounts,
      address recipient
    )
  {
    SwapValidationData calldata validationData = _decodeBeforeExecutionData(beforeExecutionData);
    address tokenIn = validationData.tokenIn;
    address tokenOut = validationData.tokenOut;
    uint256 amountIn = validationData.amountIn;

    uint256 swappedAmount =
      validationData.swapperBalanceBefore - tokenIn.balanceOf(intentData.coreData.mainAddress);
    require(swappedAmount <= amountIn, AmountInMismatch(amountIn, swappedAmount));

    uint256 amountOut = _getRecipientBalance(
      tokenOut, validationData.recipient, validationData.dstFeePercent
    ) - validationData.recipientBalanceBefore;

    uint256 price = (amountOut * DENOMINATOR) / amountIn;

    SwapHookData calldata swapHookData = _decodeHookData(intentData.coreData.hookIntentData);

    _validateSwapCondition(
      swapHookData.swapConditions[validationData.intentIndex],
      swapRecord[validationData.intentHash][validationData.intentIndex],
      price,
      amountIn,
      validationData.srcFeePercent,
      validationData.dstFeePercent,
      tokenIn,
      tokenOut
    );

    if (validationData.dstFeePercent == 0) {
      return (tokens, fees, amounts, recipient);
    }

    tokens = new address[](1);
    tokens[0] = tokenOut;

    fees = new uint256[](1);
    fees[0] = (amountOut * validationData.dstFeePercent) / PRECISION;

    amounts = new uint256[](1);
    amounts[0] = amountOut - fees[0];

    recipient = validationData.recipient;

    return (tokens, fees, amounts, recipient);
  }

  /**
   * @notice Gets the number of times a specific swap condition has been executed
   * @param intentHash The hash of the intent
   * @param intentIndex The index of the specific intent
   * @param conditionIndex The index of the swap condition to check
   * @return The number of times this condition has been executed
   */
  function getSwapExecutionCount(bytes32 intentHash, uint256 intentIndex, uint256 conditionIndex)
    public
    view
    returns (uint256)
  {
    uint256 packedValue = swapRecord[intentHash][intentIndex][conditionIndex / 32];
    uint256 bytePosition = conditionIndex % 32;

    return uint8(packedValue >> (bytePosition * 8));
  }

  function _validateSwapCondition(
    SwapCondition[] calldata swapCondition,
    mapping(uint256 swapIndexes => uint256 swapCounts) storage record,
    uint256 price,
    uint256 amountIn,
    uint256 srcFeePercent,
    uint256 dstFeePercent,
    address tokenIn,
    address tokenOut
  ) internal {
    for (uint256 i; i < swapCondition.length; ++i) {
      SwapCondition calldata condition = swapCondition[i];

      (uint128 minTime, uint128 maxTime) = condition.timeLimits.unpack();
      if (block.timestamp < minTime || block.timestamp > maxTime) {
        continue;
      }

      (uint128 minAmountIn, uint128 maxAmountIn) = condition.amountInLimits.unpack();
      if (amountIn < minAmountIn || amountIn > maxAmountIn) {
        continue;
      }

      (uint128 maxSrcFee, uint128 maxDstFee) = condition.maxFees.unpack();
      if (srcFeePercent > maxSrcFee || dstFeePercent > maxDstFee) {
        continue;
      }

      (uint128 minPrice, uint128 maxPrice) = condition.priceLimits.unpack();
      if (price < minPrice || price > maxPrice) {
        continue;
      }

      if (!OracleLib.validate(condition.oracle, tokenIn, tokenOut, price)) {
        continue;
      }

      if (!_increaseByOne(record, uint8(i), condition.swapLimit)) {
        continue;
      }
      return;
    }

    revert InvalidSwap();
  }

  /**
   * @notice Increments swap count for a specific condition index
   * @dev Uses bit manipulation to efficiently store counts in packed format
   * @param record Storage mapping containing packed swap counts
   * @param index The condition index to increment
   * @param limit Maximum allowed swaps for this condition
   * @return success True if increment was successful (within limit), false otherwise
   */
  function _increaseByOne(
    mapping(uint256 packedIndexes => uint256 packedValues) storage record,
    uint8 index,
    uint8 limit
  ) internal returns (bool) {
    uint256 packedValue = record[index / 32];
    uint256 bytePosition = index % 32;

    uint8 swapCount = uint8(packedValue >> (bytePosition * 8)) + 1;

    if (swapCount > limit) {
      return false;
    }

    packedValue += 1 << (bytePosition * 8);

    record[index / 32] = packedValue;

    return true;
  }

  function _getRecipientBalance(address tokenOut, address recipient, uint256 feePercent)
    internal
    view
    returns (uint256)
  {
    if (feePercent != 0) {
      return tokenOut.balanceOf(msg.sender);
    }
    return tokenOut.balanceOf(recipient);
  }

  // @dev: equivalent to abi.decode(data, (SwapHookData))
  function _decodeHookData(bytes calldata data)
    internal
    pure
    returns (SwapHookData calldata hookData)
  {
    assembly ('memory-safe') {
      hookData := add(data.offset, calldataload(data.offset))
    }
  }

  // @dev: equivalent to abi.encode(index, packedFees).
  function _decodeHookActionData(bytes calldata data)
    internal
    pure
    returns (uint256 index, uint256 intentSrcFee, uint256 intentDstFee)
  {
    index = data.decodeUint256(0);
    (uint128 srcFee, uint128 dstFee) = PackedU128.wrap(data.decodeUint256(1)).unpack();
    intentSrcFee = srcFee;
    intentDstFee = dstFee;
  }

  // @dev: equivalent to abi.decode(data, (SwapValidationData))
  function _decodeBeforeExecutionData(bytes calldata data)
    internal
    pure
    returns (SwapValidationData calldata validationData)
  {
    assembly ('memory-safe') {
      validationData := data.offset
    }
  }
}
