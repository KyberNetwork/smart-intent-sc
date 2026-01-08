// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {BaseConditionalHook} from '../../hooks/base/BaseConditionalHook.sol';
import {IKSSmartIntentHook} from '../../interfaces/hooks/IKSSmartIntentHook.sol';

import {TokenHelper} from 'ks-common-sc/src/libraries/token/TokenHelper.sol';

import {IPositionManager} from '../../interfaces/uniswapv4/IPositionManager.sol';
import {IERC721} from 'openzeppelin-contracts/contracts/token/ERC721/IERC721.sol';

import {ActionData} from '../../types/ActionData.sol';
import {ConditionTree, Node} from '../../types/ConditionTree.sol';
import {IntentData} from '../../types/IntentData.sol';

abstract contract BaseTickBasedRemoveLiquidityHook is BaseConditionalHook {
  using TokenHelper for address;

  event LiquidityRemoved(address nftAddress, uint256 nftId, uint256 liquidity);

  error InvalidOwner();
  error InvalidLiquidity();
  error NotEnoughOutputAmount();
  error NotEnoughFeesReceived();
  error ExceedMaxFeesPercent();

  uint256 public constant Q128 = 1 << 128;
  address public immutable WETH;

  modifier checkTokenLengths(ActionData calldata actionData) override {
    require(actionData.erc20Ids.length == 0, InvalidTokenData());
    require(actionData.erc721Ids.length == 1, InvalidTokenData());
    _;
  }

  constructor(address _weth) {
    WETH = _weth;
  }

  /**
   * @notice Data structure for remove liquidity validation
   * @param nftAddresses The NFT addresses
   * @param nftIds The NFT IDs
   * @param nodes The nodes of conditions (used to build the condition tree)
   * @param maxFees The max fee percents for each output token (1e6 = 100%), [128 bits token0 max fee, 128 bits token1 max fee]
   * @param recipient The recipient
   * @param additionalData The additional data
   */
  struct RemoveLiquidityHookData {
    address[] nftAddresses;
    uint256[] nftIds;
    Node[][] nodes;
    uint256[] maxFees;
    address recipient;
    bytes additionalData;
  }

  /**
   * @notice Data structure for remove liquidity params
   * @param index The index of validation data in RemoveLiquidityHookData struct
   * @param liquidityToRemove The liquidity to remove
   * @param wrapOrUnwrap Whether to wrap or unwrap the tokens after removing liquidity
   * @param recipient The recipient of the output tokens
   * @param poolPrice The price of the pool
   * @param currentTick The current tick of the pool
   * @param positionInfo The position info of the NFT
   */
  struct RemoveLiquidityParams {
    uint256 index;
    uint256 liquidityToRemove;
    bool wrapOrUnwrap;
    address recipient;
    uint160 sqrtPriceX96;
    int24 currentTick;
    PositionInfo positionInfo;
  }

  /**
   * @notice Data structure for output validation params
   * @param router The router address that receives the output tokens after removing liquidity
   * @param balancesBefore The token0, token1 balances of the router before removing liquidity
   * @param maxFees The max fee percents for each output token (1e6 = 100%)
   * @param intentFeesPercent The intent fees percents for each output token (1e6 = 100%)
   * @param tokens The token0, token1 of the pool
   * @param amounts The expected amounts of tokens received from removing the specified liquidity
   * @param unclaimedFees The unclaimed fees of the position
   */
  struct OutputValidationParams {
    address router;
    uint256[2] balancesBefore;
    uint256[2] maxFees;
    uint256[2] intentFeesPercent;
    address[2] tokens;
  }

  /**
   * @notice Data structure for position info
   * @param nftAddress The NFT address
   * @param nftId The NFT ID
   * @param liquidity The liquidity of the position before removing liquidity
   * @param feesGrowthInsideLast The fees growth count of token0 and token1 since last time updated
   * @param feesGenerated The fees generated of token0 and token1
   * @param ticks Position tick range [tickLower, tickUpper]
   * @param amounts The expected amounts of tokens received from removing the specified liquidity
   * @param unclaimedFees The unclaimed fees of the position
   */
  struct PositionInfo {
    address nftAddress;
    uint256 nftId;
    uint256 liquidity;
    int24[2] ticks;
    uint256[2] feesGrowthInsideLast;
    uint256[2] feesGenerated;
    uint256[2] amounts;
    uint256[2] unclaimedFees;
  }

  /// @inheritdoc IKSSmartIntentHook
  function beforeExecution(bytes32, IntentData calldata intentData, ActionData calldata actionData)
    external
    view
    override
    checkTokenLengths(actionData)
    returns (uint256[] memory, bytes memory beforeExecutionData)
  {
    // not collect fees before execution
    beforeExecutionData = _validateBeforeExecution(intentData, actionData);
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
    returns (
      address[] memory tokens,
      uint256[] memory fees,
      uint256[] memory amounts,
      address recipient
    )
  {
    (tokens, fees, amounts, recipient) = _validateAfterExecution(intentData, beforeExecutionData);
  }

  function _validateBeforeExecution(IntentData calldata intentData, ActionData calldata actionData)
    internal
    view
    virtual
    returns (bytes memory beforeExecutionData)
  {}

  function _validateAfterExecution(
    IntentData calldata intentData,
    bytes calldata beforeExecutionData
  )
    internal
    virtual
    returns (
      address[] memory tokens,
      uint256[] memory fees,
      uint256[] memory amounts,
      address recipient
    )
  {
    (RemoveLiquidityParams calldata removeLiqParams, OutputValidationParams calldata outputParams) =
      _decodeBeforeExecutionData(beforeExecutionData);

    _validateTokenOwner(
      removeLiqParams.positionInfo.nftAddress,
      removeLiqParams.positionInfo.nftId,
      intentData.coreData.mainAddress
    );
    _validateLiquidity(removeLiqParams);
    (fees, amounts) = _validateOutput(outputParams, removeLiqParams.positionInfo);

    tokens = new address[](2);
    tokens[0] = outputParams.tokens[0];
    tokens[1] = outputParams.tokens[1];
    recipient = removeLiqParams.recipient;

    emit LiquidityRemoved(
      removeLiqParams.positionInfo.nftAddress,
      removeLiqParams.positionInfo.nftId,
      removeLiqParams.liquidityToRemove
    );
  }

  /**
   * @notice Validate the output after removing liquidity
   * @param outputParams The params used to validate output after execution
   * @return fees The fees will be charged
   * @return userReceived The amounts of tokens user will receive after removing liquidity
   */
  function _validateOutput(
    OutputValidationParams calldata outputParams,
    PositionInfo calldata positionInfo
  ) internal view virtual returns (uint256[] memory fees, uint256[] memory userReceived) {
    (uint256 routerReceived0, uint256 routerReceived1) =
      _recordRouterBalances(outputParams.router, outputParams.tokens);

    routerReceived0 -= outputParams.balancesBefore[0];
    routerReceived1 -= outputParams.balancesBefore[1];

    require(
      routerReceived0 >= positionInfo.unclaimedFees[0]
        && routerReceived1 >= positionInfo.unclaimedFees[1],
      NotEnoughFeesReceived()
    );

    uint256 amount0ReceivedForLiquidity = routerReceived0 - positionInfo.unclaimedFees[0];
    uint256 amount1ReceivedForLiquidity = routerReceived1 - positionInfo.unclaimedFees[1];

    // not charge fee on the user's unclaimed fees
    fees = new uint256[](2);
    fees[0] = amount0ReceivedForLiquidity * outputParams.intentFeesPercent[0] / PRECISION;
    fees[1] = amount1ReceivedForLiquidity * outputParams.intentFeesPercent[1] / PRECISION;

    userReceived = new uint256[](2);
    userReceived[0] = routerReceived0 - fees[0];
    userReceived[1] = routerReceived1 - fees[1];

    uint256 minReceived0 = positionInfo.unclaimedFees[0]
      + (positionInfo.amounts[0] * (PRECISION - outputParams.maxFees[0])) / PRECISION;
    uint256 minReceived1 = positionInfo.unclaimedFees[1]
      + (positionInfo.amounts[1] * (PRECISION - outputParams.maxFees[1])) / PRECISION;

    require(
      userReceived[0] >= minReceived0 && userReceived[1] >= minReceived1, NotEnoughOutputAmount()
    );
  }

  function _cacheBaseData(
    RemoveLiquidityHookData calldata validationData,
    bytes calldata hookActionData,
    RemoveLiquidityParams memory removeLiqParams,
    OutputValidationParams memory outputParams
  ) internal view virtual {
    (
      removeLiqParams.index,
      removeLiqParams.positionInfo.feesGenerated[0],
      removeLiqParams.positionInfo.feesGenerated[1],
      removeLiqParams.liquidityToRemove,
      removeLiqParams.wrapOrUnwrap,
      outputParams.intentFeesPercent
    ) = _decodeHookActionData(hookActionData);
    removeLiqParams.recipient = validationData.recipient;
    removeLiqParams.positionInfo.nftAddress = validationData.nftAddresses[removeLiqParams.index];
    removeLiqParams.positionInfo.nftId = validationData.nftIds[removeLiqParams.index];

    outputParams.router = msg.sender;
    outputParams.maxFees = [
      validationData.maxFees[removeLiqParams.index] >> 128,
      uint128(validationData.maxFees[removeLiqParams.index])
    ];

    require(
      outputParams.intentFeesPercent[0] <= outputParams.maxFees[0]
        && outputParams.intentFeesPercent[1] <= outputParams.maxFees[1],
      ExceedMaxFeesPercent()
    );
  }

  function _validateConditions(
    Node[] calldata nodes,
    uint256 fee0Collected,
    uint256 fee1Collected,
    uint256 poolPrice
  ) internal view virtual {
    this.validateConditionTree(
      _buildConditionTree(nodes, fee0Collected, fee1Collected, poolPrice), 0
    );
  }

  function _validateTokenOwner(address nftAddress, uint256 nftId, address owner)
    internal
    view
    virtual
  {
    require(IERC721(nftAddress).ownerOf(nftId) == owner, InvalidOwner());
  }

  function _validateLiquidity(RemoveLiquidityParams calldata removeLiquidityParams)
    internal
    view
    virtual
  {
    require(
      _getPositionLiquidity(
        removeLiquidityParams.positionInfo.nftAddress, removeLiquidityParams.positionInfo.nftId
      ) == removeLiquidityParams.positionInfo.liquidity - removeLiquidityParams.liquidityToRemove,
      InvalidLiquidity()
    );
  }

  function _getPositionLiquidity(address nftAddress, uint256 nftId)
    internal
    view
    virtual
    returns (uint256 liquidity)
  {
    liquidity = IPositionManager(nftAddress).getPositionLiquidity(nftId);
  }

  function _recordRouterBalances(address router, address[2] memory tokens)
    internal
    view
    returns (uint256 balance0, uint256 balance1)
  {
    balance0 = tokens[0].balanceOf(router);
    balance1 = tokens[1].balanceOf(router);
  }

  function _adjustTokens(address[2] memory tokens)
    internal
    view
    returns (address[2] memory adjustedTokens)
  {
    adjustedTokens[0] = _adjustToken(tokens[0]);
    adjustedTokens[1] = _adjustToken(tokens[1]);
  }

  function _buildConditionTree(
    Node[] calldata nodes,
    uint256 fee0Collected,
    uint256 fee1Collected,
    uint256 poolPrice
  ) internal pure virtual returns (ConditionTree memory conditionTree) {
    conditionTree.nodes = nodes;
    conditionTree.additionalData = new bytes[](nodes.length);
    for (uint256 i; i < nodes.length; ++i) {
      if (!nodes[i].isLeaf() || nodes[i].condition.isType(TIME_BASED)) {
        continue;
      }
      if (nodes[i].condition.isType(YIELD_BASED)) {
        conditionTree.additionalData[i] = abi.encode(fee0Collected, fee1Collected, poolPrice);
      } else if (nodes[i].condition.isType(PRICE_BASED)) {
        conditionTree.additionalData[i] = abi.encode(poolPrice);
      }
    }
  }

  // @dev: equivalent to abi.decode(data, (RemoveLiquidityHookData))
  function _decodeHookData(bytes calldata data)
    internal
    pure
    returns (RemoveLiquidityHookData calldata validationData)
  {
    assembly ('memory-safe') {
      validationData := add(data.offset, calldataload(data.offset))
    }
  }

  // @dev: equivalent to abi.decode(data, (uint256 index, uint256 fee0Generated, uint256 fee1Generated, uint256 liquidity, bool wrapOrUnwrap, uint256 packedFees))
  function _decodeHookActionData(bytes calldata data)
    internal
    pure
    virtual
    returns (
      uint256 index,
      uint256 fee0Generated,
      uint256 fee1Generated,
      uint256 liquidity,
      bool wrapOrUnwrap,
      uint256[2] memory intentFeesPercent
    )
  {
    uint256 packedFees;
    assembly ('memory-safe') {
      index := calldataload(data.offset)
      fee0Generated := calldataload(add(data.offset, 0x20))
      fee1Generated := calldataload(add(data.offset, 0x40))
      liquidity := calldataload(add(data.offset, 0x60))
      wrapOrUnwrap := calldataload(add(data.offset, 0x80))
      packedFees := calldataload(add(data.offset, 0xa0))
    }

    intentFeesPercent = [packedFees >> 128, uint128(packedFees)];
  }

  // @dev: equivalent to abi.decode(data, (RemoveLiquidityParams, OutputValidationParams))
  function _decodeBeforeExecutionData(bytes calldata data)
    internal
    pure
    virtual
    returns (
      RemoveLiquidityParams calldata removeLiqParams,
      OutputValidationParams calldata outputParams
    )
  {
    assembly ('memory-safe') {
      removeLiqParams := data.offset
      outputParams := add(data.offset, 0x260) // (outputParams starts at slot 19 (608th byte))
    }
  }

  function _adjustToken(address token) internal view returns (address adjustedToken) {
    if (token != WETH && token != TokenHelper.NATIVE_ADDRESS) {
      return token;
    }

    return token == WETH ? TokenHelper.NATIVE_ADDRESS : WETH;
  }

  function _toNative(address token) internal pure returns (address nativeToken) {
    return token == address(0) ? TokenHelper.NATIVE_ADDRESS : token;
  }
}
