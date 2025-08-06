// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'src/validators/base/BaseIntentValidator.sol';

import 'ks-common-sc/libraries/token/TokenHelper.sol';

import 'src/interfaces/uniswapv3/IUniswapV3PM.sol';
import 'src/interfaces/uniswapv3/IUniswapV3Pool.sol';
import 'src/libraries/ConditionTreeLibrary.sol';
import 'src/libraries/uniswapv4/LiquidityAmounts.sol';
import 'src/libraries/uniswapv4/TickMath.sol';
import 'src/validators/base/BaseConditionalValidator.sol';

contract KSRemoveLiquidityUniswapV3IntentValidator is
  BaseIntentValidator,
  BaseConditionalValidator
{
  using TokenHelper for address;

  error InvalidOwner();
  error InvalidLiquidity();
  error InvalidOutputAmount();

  uint256 public constant Q128 = 1 << 128;
  address public immutable WETH;

  /**
   * @notice Local variables used for remove liquidity validation to avoid stack too deep
   * @param recipient The recipient of the output tokens
   * @param pool The pool address
   * @param positionManager The position manager contract
   * @param tokenId The token ID
   * @param liquidityToRemove The liquidity to remove
   * @param liquidityBefore The liquidity before removing liquidity
   * @param sqrtPriceX96 The sqrt price X96 of the pool
   * @param wrapOrUnwrap wrap or unwrap token flag when remove liquidity from pool
   * @param ticks The tick range of the pool [tickLower, tickCurrent, tickUpper]
   * @param feesGrowthInsideLast The fees growth count of token0 and token1 since last time updated
   * @param balancesBefore The token0, token1 balances before removing liquidity
   * @param maxFees The max fee percents for each output token (1e6 = 100%)
   * @param tokens The token0, token1 of the pool
   * @param amounts The expected amounts of tokens to remove (after claimed fees)
   * @param unclaimedFees The unclaimed fees of the position
   */
  struct LocalVar {
    address recipient;
    address pool;
    IUniswapV3PM positionManager;
    uint256 tokenId;
    uint256 liquidityToRemove;
    uint256 liquidityBefore;
    uint160 sqrtPriceX96;
    bool wrapOrUnwrap;
    int24[3] ticks;
    uint256[2] feesGrowthInsideLast;
    uint256[2] balancesBefore;
    uint256[2] maxFees;
    address[2] tokens;
    uint256[2] amounts;
    uint256[2] unclaimedFees;
  }

  /**
   * @notice Data structure for remove liquidity validation
   * @param nftAddresses The NFT addresses
   * @param nftIds The NFT IDs
   * @param pools The pool addresses
   * @param nodes The nodes of conditions (used to build the condition tree)
   * @param maxFees The max fee percents for each output token (1e6 = 100%), [128 bits token0 max fee, 128 bits token1 max fee]
   * @param recipient The recipient
   */
  struct RemoveLiquidityValidationData {
    address[] nftAddresses;
    uint256[] nftIds;
    address[] pools;
    Node[][] nodes;
    uint256[] maxFees;
    address recipient;
  }

  constructor(address _weth) {
    WETH = _weth;
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
    uint256 fee0Generated;
    uint256 fee1Generated;
    (index, fee0Generated, fee1Generated, localVar.liquidityToRemove, localVar.wrapOrUnwrap) =
      _decodeValidatorData(actionData.validatorData);

    Node[] calldata nodes = _cacheAndDecodeValidationData(coreData.validationData, localVar, index);

    this.validateConditionTree(
      _buildConditionTree(nodes, fee0Generated, fee1Generated, localVar.sqrtPriceX96), 0
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

    (,,,,,,, uint128 liquidityAfter,,,,) = localVar.positionManager.positions(localVar.tokenId);
    require(
      liquidityAfter == localVar.liquidityBefore - localVar.liquidityToRemove, InvalidLiquidity()
    );
    require(
      localVar.positionManager.ownerOf(localVar.tokenId) == coreData.mainAddress, InvalidOwner()
    );

    _validateOutput(localVar);
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
      if (nodes[i].condition.isType(YIELD_BASED)) {
        conditionTree.additionalData[i] = abi.encode(fee0Collected, fee1Collected, sqrtPriceX96);
      } else if (nodes[i].condition.isType(PRICE_BASED)) {
        conditionTree.additionalData[i] = abi.encode(sqrtPriceX96);
      }
    }
  }

  function _validateOutput(LocalVar calldata localVar) internal view {
    uint256 output0 = localVar.tokens[0].balanceOf(localVar.recipient) - localVar.balancesBefore[0];
    uint256 output1 = localVar.tokens[1].balanceOf(localVar.recipient) - localVar.balancesBefore[1];

    uint256 minOutput0 = (localVar.amounts[0] * (PRECISION - localVar.maxFees[0])) / PRECISION
      + localVar.unclaimedFees[0];
    uint256 minOutput1 = (localVar.amounts[1] * (PRECISION - localVar.maxFees[1])) / PRECISION
      + localVar.unclaimedFees[1];

    require(output0 >= minOutput0 && output1 >= minOutput1, InvalidOutputAmount());
  }

  function _cacheAndDecodeValidationData(
    bytes calldata data,
    LocalVar memory localVar,
    uint256 index
  ) internal view returns (Node[] calldata nodes) {
    RemoveLiquidityValidationData calldata validationData = _decodeValidationData(data);
    nodes = validationData.nodes[index];

    localVar.pool = validationData.pools[index];
    localVar.recipient = validationData.recipient;
    localVar.tokenId = validationData.nftIds[index];
    localVar.positionManager = IUniswapV3PM(validationData.nftAddresses[index]);
    localVar.maxFees =
      [validationData.maxFees[index] >> 128, uint128(validationData.maxFees[index])];
    (
      ,
      ,
      localVar.tokens[0],
      localVar.tokens[1],
      ,
      localVar.ticks[0],
      localVar.ticks[2],
      localVar.liquidityBefore,
      localVar.feesGrowthInsideLast[0],
      localVar.feesGrowthInsideLast[1],
      localVar.unclaimedFees[0],
      localVar.unclaimedFees[1]
    ) = localVar.positionManager.positions(localVar.tokenId);

    (localVar.sqrtPriceX96, localVar.ticks[1],,,,,) = IUniswapV3Pool(localVar.pool).slot0();

    if (localVar.wrapOrUnwrap) {
      localVar.tokens = [_adjustToken(localVar.tokens[0]), _adjustToken(localVar.tokens[1])];
    }

    localVar.balancesBefore = [
      localVar.tokens[0].balanceOf(localVar.recipient),
      localVar.tokens[1].balanceOf(localVar.recipient)
    ];

    _computePositionValues(localVar);
  }

  function _decodeValidatorData(bytes calldata data)
    internal
    pure
    returns (
      uint256 index,
      uint256 fee0Collected,
      uint256 fee1Collected,
      uint256 liquidity,
      bool wrapOrUnwrap
    )
  {
    assembly ("memory-safe") {
      index := calldataload(data.offset)
      fee0Collected := calldataload(add(data.offset, 0x20))
      fee1Collected := calldataload(add(data.offset, 0x40))
      liquidity := calldataload(add(data.offset, 0x60))
      wrapOrUnwrap := calldataload(add(data.offset, 0x80))
    }
  }

  function _decodeBeforeExecutionData(bytes calldata data)
    internal
    pure
    returns (LocalVar calldata localVar)
  {
    assembly ("memory-safe") {
      localVar := data.offset
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

  function _adjustToken(address token) internal view returns (address adjustedToken) {
    return token == WETH ? TokenHelper.NATIVE_ADDRESS : token;
  }

  function _computePositionValues(LocalVar memory localVar) internal view {
    if (localVar.liquidityToRemove != 0) {
      uint160 sqrtPriceLower = TickMath.getSqrtRatioAtTick(localVar.ticks[0]);
      uint160 sqrtPriceUpper = TickMath.getSqrtRatioAtTick(localVar.ticks[2]);
      (localVar.amounts[0], localVar.amounts[1]) = LiquidityAmounts.getAmountsForLiquidity(
        localVar.sqrtPriceX96, sqrtPriceLower, sqrtPriceUpper, uint128(localVar.liquidityToRemove)
      );
    }

    (uint256 feeGrowthInside0, uint256 feeGrowthInside1) = _getFeeGrowthInside(
      IUniswapV3Pool(localVar.pool), localVar.ticks[0], localVar.ticks[1], localVar.ticks[2]
    );

    unchecked {
      localVar.unclaimedFees[0] += Math.mulDiv(
        feeGrowthInside0 - localVar.feesGrowthInsideLast[0], localVar.liquidityBefore, Q128
      );
      localVar.unclaimedFees[1] += Math.mulDiv(
        feeGrowthInside1 - localVar.feesGrowthInsideLast[1], localVar.liquidityBefore, Q128
      );
    }
  }

  function _getFeeGrowthInside(
    IUniswapV3Pool pool,
    int24 tickLower,
    int24 tickCurrent,
    int24 tickUpper
  ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
    (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) =
      (pool.feeGrowthGlobal0X128(), pool.feeGrowthGlobal1X128());
    (,, uint256 feeGrowthOutside0X128Lower, uint256 feeGrowthOutside1X128Lower,,,,) =
      pool.ticks(tickLower);
    (,, uint256 feeGrowthOutside0X128Upper, uint256 feeGrowthOutside1X128Upper,,,,) =
      pool.ticks(tickUpper);

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
}
