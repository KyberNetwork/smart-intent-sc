// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc/src/libraries/token/TokenHelper.sol';
import 'src/hooks/base/BaseConditionalHook.sol';
import 'src/hooks/base/BaseStatefulHook.sol';

contract KSConditionalSwapHook is BaseStatefulHook, BaseConditionalHook {
  using TokenHelper for address;

  error InvalidTokenIn(address tokenIn, address actualTokenIn);
  error AmountInMismatch(uint256 amountIn, uint256 actualAmountIn);
  error InvalidSwap();

  uint256 public constant DENOMINATOR = 1e18;

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
   * @param startTime The start time of the swap
   * @param endTime The end time of the swap
   * @param amountInLimits The limits of the swap amount (minAmountIn 128bits, maxAmountIn 128bits)
   * @param maxFees The max fees (srcFee 128bits, dstFee 128bits)
   * @param priceLimits The limits of price (tokenOut/tokenIn denominated by 1e18) (minPrice 128bits, maxPrice 128bits)
   */
  struct SwapCondition {
    uint8 swapLimit;
    uint256 startTime;
    uint256 endTime;
    uint256 amountInLimits;
    uint256 maxFees;
    uint256 priceLimits;
  }

  struct SwapValidationData {
    SwapCondition[] swapConditions;
    bytes32 intentHash;
    uint256 intentIndex;
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
    uint256 routerBalanceBefore;
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

  modifier checkTokenLengths(TokenData calldata tokenData) override {
    require(tokenData.erc20Data.length == 1, InvalidTokenData());
    require(tokenData.erc721Data.length == 0, InvalidTokenData());
    _;
  }

  /// @inheritdoc IKSSmartIntentHook
  function beforeExecution(
    bytes32 intentHash,
    IntentCoreData calldata coreData,
    ActionData calldata actionData
  )
    external
    override
    onlyWhitelistedRouter
    checkTokenLengths(actionData.tokenData)
    returns (uint256[] memory fees, bytes memory beforeExecutionData)
  {
    SwapHookData calldata swapHookData = _decodeHookData(coreData.hookIntentData);
    (uint256 index, uint256 intentSrcFee, uint256 intentDstFee) =
      _decodeAndValidateHookActionData(actionData.hookActionData, swapHookData);

    address tokenIn = actionData.tokenData.erc20Data[0].token;
    address tokenOut = swapHookData.dstTokens[index];
    uint256 amountIn = actionData.tokenData.erc20Data[0].amount;

    require(
      tokenIn == swapHookData.srcTokens[index],
      InvalidTokenIn(tokenIn, swapHookData.srcTokens[index])
    );

    fees = new uint256[](1);
    fees[0] = (amountIn * intentSrcFee) / PRECISION;
    beforeExecutionData = abi.encode(
      SwapValidationData({
        swapConditions: swapHookData.swapConditions[index],
        intentHash: intentHash,
        intentIndex: index,
        tokenIn: tokenIn,
        tokenOut: tokenOut,
        amountIn: amountIn,
        srcFeePercent: intentSrcFee,
        dstFeePercent: intentDstFee,
        routerBalanceBefore: tokenOut.balanceOf(msg.sender),
        swapperBalanceBefore: tokenIn.balanceOf(coreData.mainAddress),
        recipient: swapHookData.recipient
      })
    );
  }

  /// @inheritdoc IKSSmartIntentHook
  function afterExecution(
    bytes32,
    IntentCoreData calldata coreData,
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
      validationData.swapperBalanceBefore - tokenIn.balanceOf(coreData.mainAddress);
    require(swappedAmount == amountIn, AmountInMismatch(amountIn, swappedAmount));

    uint256 amountOut = tokenOut.balanceOf(msg.sender) - validationData.routerBalanceBefore;

    uint256 price = (amountOut * DENOMINATOR) / amountIn;

    _validateSwapCondition(
      validationData.swapConditions,
      swapRecord[validationData.intentHash][validationData.intentIndex],
      price,
      amountIn,
      validationData.srcFeePercent,
      validationData.dstFeePercent
    );

    tokens = new address[](1);
    tokens[0] = tokenOut;

    fees = new uint256[](1);
    fees[0] = (amountOut * validationData.dstFeePercent) / PRECISION;

    amounts = new uint256[](1);
    amounts[0] = amountOut - fees[0];

    recipient = validationData.recipient;
  }

  /**
   * @notice Gets the number of times a specific swap condition has been executed
   * @param intentHash The hash of the intent
   * @param intentIndex The index of the specific intent
   * @param conditionIndex The index of the swap condition to check
   * @return executionCount The number of times this condition has been executed
   */
  function getSwapExecutionCount(bytes32 intentHash, uint256 intentIndex, uint256 conditionIndex)
    public
    view
    returns (uint256 executionCount)
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
    uint256 dstFeePercent
  ) internal {
    for (uint256 i; i < swapCondition.length; ++i) {
      SwapCondition calldata condition = swapCondition[i];

      if (block.timestamp < condition.startTime || block.timestamp > condition.endTime) {
        continue;
      }

      if (
        amountIn < condition.amountInLimits >> 128 || amountIn > uint128(condition.amountInLimits)
      ) {
        continue;
      }

      if (srcFeePercent > condition.maxFees >> 128 || dstFeePercent > uint128(condition.maxFees)) {
        continue;
      }

      if (price < condition.priceLimits >> 128 || price > uint128(condition.priceLimits)) {
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

    uint256 mask = 0xFF << (bytePosition * 8);
    packedValue &= ~mask;
    packedValue |= (uint256(swapCount) << (bytePosition * 8));

    record[index / 32] = packedValue;

    return true;
  }

  // @dev: equivalent to abi.decode(data, (SwapCondition))
  function _decodeSwapCondition(bytes calldata data)
    internal
    pure
    returns (SwapCondition calldata swapCondition)
  {
    assembly ("memory-safe") {
      swapCondition := data.offset
    }
  }

  // @dev: equivalent to abi.decode(data, (SwapHookData))
  function _decodeHookData(bytes calldata data)
    internal
    pure
    returns (SwapHookData calldata hookData)
  {
    assembly ("memory-safe") {
      hookData := add(data.offset, calldataload(data.offset))
    }
  }

  // @dev: equivalent to abi.decode(data, (uint256, uint256, uint256, uint256))
  function _decodeAndValidateHookActionData(bytes calldata data, SwapHookData calldata swapHookData)
    internal
    view
    returns (uint256 index, uint256 intentSrcFee, uint256 intentDstFee)
  {
    uint256 packedFees;
    assembly ("memory-safe") {
      index := calldataload(data.offset)
      packedFees := calldataload(add(data.offset, 0x20))
    }

    intentSrcFee = packedFees >> 128;
    intentDstFee = uint128(packedFees);
  }

  // @dev: equivalent to abi.decode(data, (SwapValidationData))
  function _decodeBeforeExecutionData(bytes calldata data)
    internal
    pure
    returns (SwapValidationData calldata validationData)
  {
    assembly ("memory-safe") {
      validationData := add(data.offset, calldataload(data.offset))
    }
  }
}
