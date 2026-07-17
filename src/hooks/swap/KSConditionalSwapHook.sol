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
import {MerkleProof} from 'openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol';

contract KSConditionalSwapHook is BaseStatefulHook {
  using TokenHelper for address;
  using CalldataDecoder for bytes;

  error InvalidProof();
  error InvalidSwapTime(uint256 timestamp, uint128 minTime, uint128 maxTime);
  error InvalidSwapAmountIn(uint256 amountIn, uint128 minAmountIn, uint128 maxAmountIn);
  error InvalidSwapFee(
    uint256 srcFeePercent, uint256 dstFeePercent, uint128 maxSrcFee, uint128 maxDstFee
  );
  error InvalidSwapPrice(uint256 price, uint128 minPrice, uint128 maxPrice);
  error MaxConditionIndex();
  error SwapLimitExceeded(uint256 conditionIndex, uint8 swapLimit);

  uint256 public constant DENOMINATOR = 1e18;
  uint256 public constant PRECISION = 1_000_000;

  /**
   * @notice Data structure for conditional swap
   * @param root The merkle root committing to the allowed swap leaves, where each leaf is
   *        keccak256(abi.encode(leafIndex, tokenIn, tokenOut, condition))
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
    SwapCondition swapCondition;
    bytes32 intentHash;
    uint256 leafIndex;
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
    uint256 holderBalanceBefore;
    uint256 swapperBalanceBefore;
    uint256 srcFeeRate;
    uint256 dstFeeRate;
    address recipient;
  }

  /**
   * @notice Tracks swap execution counts for each condition to enforce swap limits
   * @dev Maps intentHash -> packedIndexes -> packedCounts
   *      Each uint256 stores up to 32 uint8 swap counts (8 bits each), indexed by swapIndexes / 32
   *      Individual counts are extracted using bit shifts based on swapIndexes % 32
   */
  mapping(bytes32 intentHash => mapping(uint256 swapIndexes => uint256 swapCount)) public
    swapRecord;

  constructor(address[] memory initialRouters) BaseStatefulHook(initialRouters) {}

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
    SwapHookData calldata swapHookData = _decodeHookData(intentData.coreData.hookIntentData);
    (
      bytes32[] calldata proof,
      SwapCondition calldata condition,
      uint256 leafIndex,
      address tokenOut,
      uint256 intentSrcFeeRate,
      uint256 intentDstFeeRate
    ) = _decodeHookActionData(actionData.hookActionData);

    address tokenIn = intentData.tokenData.erc20Data[actionData.erc20Ids[0]].token;

    bytes32 leaf = keccak256(abi.encode(leafIndex, tokenIn, tokenOut, condition));
    require(MerkleProof.verifyCalldata(proof, swapHookData.root, leaf), InvalidProof());

    uint256 amountIn = actionData.erc20Amounts[0];

    fees = new uint256[](1);
    fees[0] = (amountIn * intentSrcFeeRate) / PRECISION;
    beforeExecutionData = abi.encode(
      SwapValidationData({
        swapCondition: condition,
        intentHash: intentHash,
        leafIndex: leafIndex,
        tokenIn: tokenIn,
        tokenOut: tokenOut,
        amountIn: amountIn,
        holderBalanceBefore: tokenOut.balanceOf(
          _settlementHolder(swapHookData.recipient, intentDstFeeRate)
        ),
        swapperBalanceBefore: tokenIn.balanceOf(intentData.coreData.mainAddress),
        srcFeeRate: intentSrcFeeRate,
        dstFeeRate: intentDstFeeRate,
        recipient: swapHookData.recipient
      })
    );

    return (fees, beforeExecutionData);
  }

  /// @inheritdoc IKSSmartIntentHook
  function afterExecution(
    bytes32,
    IntentData calldata,
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

    uint256 amountOut = tokenOut.balanceOf(
      _settlementHolder(validationData.recipient, validationData.dstFeeRate)
    ) - validationData.holderBalanceBefore;
    uint256 dstFee = (amountOut * validationData.dstFeeRate) / PRECISION;
    uint256 netAmountOut = amountOut - dstFee;

    uint256 netExecutionPrice = (netAmountOut * DENOMINATOR) / amountIn;

    _validateSwapCondition(
      validationData.swapCondition,
      swapRecord[validationData.intentHash],
      validationData.leafIndex,
      netExecutionPrice,
      amountIn,
      validationData.srcFeeRate,
      validationData.dstFeeRate,
      tokenIn,
      tokenOut
    );

    if (validationData.dstFeeRate == 0) {
      return (tokens, fees, amounts, recipient);
    }

    tokens = new address[](1);
    tokens[0] = tokenOut;

    fees = new uint256[](1);
    fees[0] = dstFee;

    amounts = new uint256[](1);
    amounts[0] = netAmountOut;

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
    mapping(uint256 swapIndexes => uint256 swapCounts) storage record,
    uint256 conditionIndex,
    uint256 price,
    uint256 amountIn,
    uint256 srcFeePercent,
    uint256 dstFeePercent,
    address tokenIn,
    address tokenOut
  ) internal {
    (uint128 minTime, uint128 maxTime) = condition.timeLimits.unpack();
    if (block.timestamp < minTime || block.timestamp > maxTime) {
      revert InvalidSwapTime(block.timestamp, minTime, maxTime);
    }

    (uint128 minAmountIn, uint128 maxAmountIn) = condition.amountInLimits.unpack();
    if (amountIn < minAmountIn || amountIn > maxAmountIn) {
      revert InvalidSwapAmountIn(amountIn, minAmountIn, maxAmountIn);
    }

    (uint128 maxSrcFee, uint128 maxDstFee) = condition.maxFees.unpack();
    if (srcFeePercent > maxSrcFee || dstFeePercent > maxDstFee) {
      revert InvalidSwapFee(srcFeePercent, dstFeePercent, maxSrcFee, maxDstFee);
    }

    (uint128 minPrice, uint128 maxPrice) = condition.priceLimits.unpack();
    if (price < minPrice || price > maxPrice) {
      revert InvalidSwapPrice(price, minPrice, maxPrice);
    }
    if (
      condition.oracle.oracleIn.source.addressValue() != address(0)
        || condition.oracle.oracleOut.source.addressValue() != address(0)
    ) {
      OracleLib.validate(condition.oracle, tokenIn, tokenOut, price);
    }

    if (condition.swapLimit != 0) {
      _increaseByOne(record, conditionIndex, condition.swapLimit);
    }
  }

  /**
   * @notice Increments swap count for a specific condition index
   * @dev Uses bit manipulation to efficiently store counts in packed format.
   *      Each uint256 slot holds 32 uint8 counters; the slot is selected by index/32
   *      and the byte position within that slot by index%32.
   * @param record Storage mapping containing packed swap counts
   * @param index The condition index to increment
   * @param limit Maximum allowed swaps for this condition. Zero skips tracking and limit checks.
   */
  function _increaseByOne(
    mapping(uint256 packedIndexes => uint256 packedValues) storage record,
    uint256 index,
    uint8 limit
  ) internal {
    require(index <= type(uint8).max, MaxConditionIndex());
    uint256 slotKey = index / 32;
    uint256 shift = (index % 32) * 8;
    uint256 packedValue = record[slotKey];

    uint8 swapCount = uint8(packedValue >> shift) + 1;

    if (swapCount > limit) {
      revert SwapLimitExceeded(index, limit);
    }

    record[slotKey] = packedValue + (1 << shift);
  }

  function _settlementHolder(address recipient, uint256 feeRate) internal view returns (address) {
    return feeRate != 0 ? msg.sender : recipient;
  }

  // @dev: equivalent to abi.decode(data, (SwapHookData)), SwapHookData is a static struct
  //       so its head is encoded in place.
  function _decodeHookData(bytes calldata data)
    internal
    pure
    returns (SwapHookData calldata hookData)
  {
    assembly ('memory-safe') {
      hookData := data.offset
    }
  }

  // @dev: equivalent to abi.decode(data, (bytes32[], uint256, address, uint256, SwapCondition)).
  //       SwapCondition is dynamic (it carries OracleConfig), so its head slot holds an offset.
  function _decodeHookActionData(bytes calldata data)
    internal
    pure
    returns (
      bytes32[] calldata proof,
      SwapCondition calldata condition,
      uint256 leafIndex,
      address tokenOut,
      uint256 intentSrcFee,
      uint256 intentDstFee
    )
  {
    PackedU128 packedFees;
    assembly ('memory-safe') {
      leafIndex := calldataload(add(data.offset, 0x20))
      tokenOut := calldataload(add(data.offset, 0x40))
      packedFees := calldataload(add(data.offset, 0x60))
      condition := add(data.offset, calldataload(add(data.offset, 0x80)))
    }

    (uint256 length, uint256 offset) = data.decodeLengthOffset(0);
    assembly ('memory-safe') {
      proof.length := length
      proof.offset := offset
    }

    (intentSrcFee, intentDstFee) = packedFees.unpack();
  }

  // @dev: equivalent to abi.decode(data, (SwapValidationData)), SwapValidationData is a dynamic
  //       struct (it carries SwapCondition), so the encoding starts with an offset.
  function _decodeBeforeExecutionData(bytes calldata data)
    internal
    pure
    returns (SwapValidationData calldata validationData)
  {
    assembly ('memory-safe') {
      validationData := add(data.offset, calldataload(data.offset))
    }
  }
}
