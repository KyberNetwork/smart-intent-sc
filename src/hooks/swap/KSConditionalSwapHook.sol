// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc/src/libraries/token/TokenHelper.sol';
import 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import 'src/hooks/base/BaseConditionalHook.sol';
import 'src/hooks/base/BaseStatefulHook.sol';

contract KSConditionalSwapHook is BaseStatefulHook, BaseConditionalHook {
  using TokenHelper for address;

  error InvalidTokenIn(address tokenIn, address actualTokenIn);
  error AmountInTooSmallOrTooLarge(uint256 amountIn, uint256 minAmountIn, uint256 maxAmountIn);
  error AmountInMismatch(uint256 amountIn, uint256 actualAmountIn);
  error ExceedNumSwaps(uint256 swapNo, uint256 limit);
  error ExceedFeeLimit(uint256 srcFee, uint256 dstFee, uint256 maxSrcFee, uint256 maxDstFee);

  uint256 public constant DENOMINATOR = 1e18;

  /**
   * @notice Data structure for conditional swap
   * @param nodes The nodes of the condition tree
   * @param srcTokens The source tokens
   * @param dstTokens The destination tokens
   * @param swapLimits The swap limits
   * @param amountInLimits The amount in limits (minAmountIn 128bits, maxAmountIn 128bits)
   * @param maxFees The max fees (srcFee 128bits, dstFee 128bits)
   * @param recipient The recipient of the destination token
   */
  struct SwapHookData {
    Node[][] nodes;
    address[] srcTokens;
    address[] dstTokens;
    uint256[] swapLimits;
    uint256[] amountInLimits;
    uint256[] maxFees;
    address recipient;
  }

  struct SwapValidationData {
    Node[] nodes;
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
    uint256 routerBalanceBefore;
    uint256 swapperBalanceBefore;
    uint256 dstFeePercent;
    address swapper;
  }

  mapping(bytes32 intentHash => mapping(address tokenIn => mapping(address tokenOut => uint256)))
    public latestSwap;

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

    {
      uint256 minAmountIn = swapHookData.amountInLimits[index] >> 128;
      uint256 maxAmountIn = uint256(uint128(swapHookData.amountInLimits[index]));

      uint256 swapNo = ++latestSwap[intentHash][tokenIn][tokenOut];
      uint256 limit = swapHookData.swapLimits[index];

      require(swapNo <= limit, ExceedNumSwaps(swapNo, limit));
      require(
        amountIn >= minAmountIn && amountIn <= maxAmountIn,
        AmountInTooSmallOrTooLarge(amountIn, minAmountIn, maxAmountIn)
      );
      require(
        tokenIn == swapHookData.srcTokens[index],
        InvalidTokenIn(tokenIn, swapHookData.srcTokens[index])
      );
    }

    fees = new uint256[](1);
    fees[0] = (amountIn * intentSrcFee) / PRECISION;
    beforeExecutionData = abi.encode(
      SwapValidationData({
        nodes: swapHookData.nodes[index],
        tokenIn: tokenIn,
        tokenOut: tokenOut,
        amountIn: amountIn,
        dstFeePercent: intentDstFee,
        routerBalanceBefore: tokenOut.balanceOf(msg.sender),
        swapperBalanceBefore: tokenIn.balanceOf(coreData.mainAddress),
        swapper: coreData.mainAddress
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
    view
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
      validationData.swapperBalanceBefore - tokenIn.balanceOf(validationData.swapper);
    require(swappedAmount == amountIn, AmountInMismatch(amountIn, swappedAmount));

    // Get token decimals to normalize amounts
    uint8 tokenInDecimals = IERC20Metadata(tokenIn).decimals();
    uint8 tokenOutDecimals = IERC20Metadata(tokenOut).decimals();

    uint256 amountOut = tokenOut.balanceOf(msg.sender) - validationData.routerBalanceBefore;

    uint256 num = amountOut * (10 ** (_abs(18, tokenOutDecimals)));
    uint256 den = amountIn * (10 ** (_abs(18, tokenInDecimals)));

    uint256 price = (num * DENOMINATOR) / den;

    this.validateConditionTree(_buildConditionTree(validationData.nodes, price), 0);

    tokens = new address[](1);
    tokens[0] = tokenOut;

    fees = new uint256[](1);
    fees[0] = (amountOut * validationData.dstFeePercent) / PRECISION;

    amounts = new uint256[](1);
    amounts[0] = amountOut - fees[0];

    recipient = validationData.swapper;
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

  // @dev: equivalent to abi.decode(data, (uint256, uint256))
  function _decodeAndValidateHookActionData(bytes calldata data, SwapHookData calldata swapHookData)
    internal
    pure
    virtual
    returns (uint256 index, uint256 intentSrcFee, uint256 intentDstFee)
  {
    uint256 packedFees;
    assembly ("memory-safe") {
      index := calldataload(data.offset)
      packedFees := calldataload(add(data.offset, 0x20))
    }

    intentSrcFee = packedFees >> 128;
    intentDstFee = uint128(packedFees);
    uint256 maxSrcFee = swapHookData.maxFees[index] >> 128;
    uint256 maxDstFee = uint128(swapHookData.maxFees[index]);

    require(
      intentSrcFee <= maxSrcFee && intentDstFee <= maxDstFee,
      ExceedFeeLimit(intentSrcFee, intentDstFee, maxSrcFee, maxDstFee)
    );
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

  function _buildConditionTree(Node[] calldata nodes, uint256 price)
    internal
    pure
    virtual
    returns (ConditionTree memory conditionTree)
  {
    conditionTree.nodes = nodes;
    conditionTree.additionalData = new bytes[](nodes.length);
    for (uint256 i; i < nodes.length; ++i) {
      if (!nodes[i].isLeaf() || nodes[i].condition.isType(TIME_BASED)) {
        continue;
      }
      if (nodes[i].condition.isType(PRICE_BASED)) {
        conditionTree.additionalData[i] = abi.encode(price);
      } else {
        revert WrongConditionType();
      }
    }
  }

  function _abs(uint256 a, uint256 b) internal pure returns (uint256) {
    return a > b ? (a - b) : (b - a);
  }
}
