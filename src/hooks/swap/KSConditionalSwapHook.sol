// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {CalldataDecoder} from 'ks-common-sc/src/libraries/calldata/CalldataDecoder.sol';
import {TokenHelper} from 'ks-common-sc/src/libraries/token/TokenHelper.sol';
import {MerkleProof} from 'openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol';
import {ActionData, BaseStatefulHook, IntentData} from 'src/hooks/base/BaseStatefulHook.sol';
import {PackedU128} from 'src/libraries/types/PackedU128.sol';

contract KSConditionalSwapHook is BaseStatefulHook {
  using TokenHelper for address;
  using CalldataDecoder for bytes;

  error InvalidTokenIn(address tokenIn, address actualTokenIn);
  error AmountInMismatch(uint256 amountIn, uint256 actualAmountIn);
  error InvalidProof();
  error InvalidTime(uint256 timestamp, uint256 min, uint256 maxT);
  error InvalidAmountIn(uint256 amountIn, uint256 minAmountIn, uint256 maxAmountIn);
  error InvalidFees(
    uint256 srcFeePercent, uint256 dstFeePercent, uint256 maxSrcFee, uint256 maxDstFee
  );
  error InvalidPrice(uint256 price, uint256 minPrice, uint256 maxPrice);
  error InvalidSwapLimit(uint256 swapCount, uint256 limit);

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
    bytes32 root;
    address recipient;
  }

  /**
   * @notice The limit of swap executions that can be performed for a swap info
   * @param swapLimit The maximum number of times the swap can be executed
   * @param timeLimits The limits of the swap time (minTime 128bits, maxTime 128bits)
   * @param amountInLimits The limits of the swap amount (minAmountIn 128bits, maxAmountIn 128bits)
   * @param maxFees The max fees (srcFee 128bits, dstFee 128bits)
   * @param priceLimits The limits of price (tokenOut/tokenIn denominated by 1e18) (minPrice 128bits, maxPrice 128bits)
   */
  struct SwapCondition {
    uint8 swapLimit;
    PackedU128 timeLimits;
    PackedU128 amountInLimits;
    PackedU128 maxFees;
    PackedU128 priceLimits;
  }

  struct SwapValidationData {
    SwapCondition swapCondition;
    bytes32 intentHash;
    uint256 leafIndex;
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
   * @dev Maps intentHash -> packedIndexes -> packedCounts
   *      Each uint256 stores up to 32 uint8 swap counts (8 bits each), indexed by swapIndexes / 32
   *      Individual counts are extracted using bit shifts based on swapIndexes % 32
   */
  mapping(bytes32 intentHash => mapping(uint256 swapIndexes => uint256 swapCount)) public swapRecord;

  constructor(address[] memory initialRouters) BaseStatefulHook(initialRouters) {}

  modifier checkTokenLengths(ActionData calldata actionData) override {
    require(actionData.erc20Ids.length == 1, InvalidTokenData());
    require(actionData.erc721Ids.length == 0, InvalidTokenData());
    _;
  }

  function beforeExecution(
    bytes32 intentHash,
    IntentData calldata intentData,
    ActionData calldata actionData
  )
    external
    override
    onlyWhitelistedRouter
    checkTokenLengths(actionData)
    returns (uint256[] memory fees, bytes memory beforeExecutionData)
  {
    SwapHookData calldata swapHookData = _decodeHookData(intentData.coreData.hookIntentData);
    (
      bytes32[] calldata proof,
      SwapCondition calldata condition,
      uint256 leafIndex,
      address tokenIn,
      address tokenOut,
      uint256 intentSrcFee,
      uint256 intentDstFee
    ) = _decodeHookActionData(actionData.hookActionData);

    address intentTokenIn = intentData.tokenData.erc20Data[actionData.erc20Ids[0]].token;

    require(tokenIn == intentTokenIn, InvalidTokenIn(tokenIn, intentTokenIn));

    bytes32 conditionHash = keccak256(abi.encode(condition));
    bytes32 leaf = keccak256(abi.encodePacked(leafIndex, tokenIn, tokenOut, conditionHash));
    require(MerkleProof.verifyCalldata(proof, swapHookData.root, leaf), InvalidProof());

    uint256 amountIn = actionData.erc20Amounts[0];
    fees = new uint256[](1);
    fees[0] = (amountIn * intentSrcFee) / PRECISION;
    beforeExecutionData = abi.encode(
      SwapValidationData({
        swapCondition: condition,
        intentHash: intentHash,
        leafIndex: leafIndex,
        tokenIn: tokenIn,
        tokenOut: tokenOut,
        amountIn: amountIn,
        srcFeePercent: intentSrcFee,
        dstFeePercent: intentDstFee,
        recipientBalanceBefore: _getRecipientBalance(tokenOut, swapHookData.recipient, intentDstFee), // if dstFee is 0, transfer directly to the recipient
        swapperBalanceBefore: tokenIn.balanceOf(intentData.coreData.mainAddress),
        recipient: swapHookData.recipient
      })
    );

    return (fees, beforeExecutionData);
  }

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

    _validateSwapCondition(
      validationData.swapCondition,
      validationData.leafIndex,
      swapRecord[validationData.intentHash],
      price,
      amountIn,
      validationData.srcFeePercent,
      validationData.dstFeePercent
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
   * @param conditionIndex The index of the swap condition to check
   * @return The number of times this condition has been executed
   */
  function getSwapExecutionCount(bytes32 intentHash, uint256 conditionIndex)
    public
    view
    returns (uint256)
  {
    uint256 packedValue = swapRecord[intentHash][conditionIndex / 32];
    uint256 bytePosition = conditionIndex % 32;

    return uint8(packedValue >> (bytePosition * 8));
  }

  function _validateSwapCondition(
    SwapCondition calldata condition,
    uint256 index,
    mapping(uint256 swapIndexes => uint256 swapCounts) storage record,
    uint256 price,
    uint256 amountIn,
    uint256 srcFeePercent,
    uint256 dstFeePercent
  ) internal {
    if (
      block.timestamp < condition.timeLimits.value0()
        || block.timestamp > condition.timeLimits.value1()
    ) {
      revert InvalidTime(
        block.timestamp, condition.timeLimits.value0(), condition.timeLimits.value1()
      );
    }

    if (
      amountIn < condition.amountInLimits.value0() || amountIn > condition.amountInLimits.value1()
    ) {
      revert InvalidAmountIn(
        amountIn, condition.amountInLimits.value0(), condition.amountInLimits.value1()
      );
    }

    if (srcFeePercent > condition.maxFees.value0() || dstFeePercent > condition.maxFees.value1()) {
      revert InvalidFees(
        srcFeePercent, dstFeePercent, condition.maxFees.value0(), condition.maxFees.value1()
      );
    }

    if (price < condition.priceLimits.value0() || price > condition.priceLimits.value1()) {
      revert InvalidPrice(price, condition.priceLimits.value0(), condition.priceLimits.value1());
    }

    (bool success, uint8 swapCount) = _increaseByOne(record, uint8(index), condition.swapLimit);
    if (!success) {
      revert InvalidSwapLimit(swapCount, condition.swapLimit);
    }
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
  ) internal returns (bool, uint8) {
    uint256 packedValue = record[index / 32];
    uint256 bytePosition = index % 32;

    uint8 swapCount = uint8(packedValue >> (bytePosition * 8)) + 1;

    if (swapCount > limit) {
      return (false, swapCount);
    }

    packedValue += 1 << (bytePosition * 8);

    record[index / 32] = packedValue;

    return (true, swapCount);
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
    assembly ("memory-safe") {
      hookData := data.offset
    }
  }

  // @dev: equivalent to abi.decode(data, (uint256, uint256, uint256, uint256))
  function _decodeHookActionData(bytes calldata data)
    internal
    pure
    returns (
      bytes32[] calldata proof,
      SwapCondition calldata condition,
      uint256 leafIndex,
      address tokenIn,
      address tokenOut,
      uint256 intentSrcFee,
      uint256 intentDstFee
    )
  {
    PackedU128 packedFees;
    assembly ("memory-safe") {
      leafIndex := calldataload(add(data.offset, 0x20))
      tokenIn := calldataload(add(data.offset, 0x40))
      tokenOut := calldataload(add(data.offset, 0x60))
      packedFees := calldataload(add(data.offset, 0x80))
      condition := add(data.offset, 0xa0)
    }

    (uint256 length, uint256 offset) = data.decodeLengthOffset(0);
    assembly ("memory-safe") {
      proof.length := length
      proof.offset := offset
    }

    intentSrcFee = packedFees.value0();
    intentDstFee = packedFees.value1();
  }

  // @dev: equivalent to abi.decode(data, (SwapValidationData))
  function _decodeBeforeExecutionData(bytes calldata data)
    internal
    pure
    returns (SwapValidationData calldata validationData)
  {
    assembly ("memory-safe") {
      validationData := data.offset
    }
  }
}
