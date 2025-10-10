// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc/src/libraries/token/TokenHelper.sol';
import 'src/hooks/base/BaseConditionalHook.sol';
import 'src/interfaces/uniswapv2/IUniswapV2Pair.sol';
import {PackedU128, toPackedU128} from 'src/libraries/types/PackedU128.sol';

contract KSRemoveLiquidityUniswapV2Hook is BaseConditionalHook {
  using TokenHelper for address;
  using CalldataDecoder for bytes;

  error InvalidBalance();
  error InvalidLpValues();
  error InvalidFees();

  struct UniswapV2Params {
    address[] pairs;
    Node[][] nodes;
    PackedU128[] maxFees;
    address recipient;
  }

  modifier checkTokenLengths(ActionData calldata actionData) override {
    require(actionData.erc20Ids.length == 1, InvalidTokenData());
    require(actionData.erc721Ids.length == 0, InvalidTokenData());
    _;
  }

  uint256 public constant DENOMINATOR = 1e18;

  function beforeExecution(bytes32, IntentData calldata intentData, ActionData calldata actionData)
    external
    view
    override
    checkTokenLengths(actionData)
    returns (uint256[] memory fees, bytes memory beforeExecutionData)
  {
    // not collect fees before execution
    UniswapV2Params calldata uniswapV2 = _decodeHookData(intentData.coreData.hookIntentData);
    (uint256 index, PackedU128 feesGenerated, PackedU128 dstFeesPercent) =
      _decodeHookActionData(actionData.hookActionData);

    uint256 lpAmount = actionData.erc20Amounts[actionData.erc20Ids[0]];
    address pair = uniswapV2.pairs[index];
    address token0 = IUniswapV2Pair(pair).token0();
    address token1 = IUniswapV2Pair(pair).token1();
    uint256 balance0 = token0.balanceOf(pair);
    uint256 balance1 = token1.balanceOf(pair);

    require(
      dstFeesPercent.value0() <= uniswapV2.maxFees[index].value0()
        && dstFeesPercent.value1() <= uniswapV2.maxFees[index].value1(),
      InvalidFees()
    );

    _validateConditions(
      uniswapV2.nodes[index],
      feesGenerated.value0(),
      feesGenerated.value1(),
      balance0 * DENOMINATOR / balance1
    );

    // not collect fees before execution
    beforeExecutionData = abi.encode(
      pair,
      token0,
      token1,
      pair.balanceOf(intentData.coreData.mainAddress),
      lpAmount,
      uniswapV2.recipient,
      dstFeesPercent,
      _calculateLpValues(pair, balance0, balance1, lpAmount),
      toPackedU128(token0.balanceOf(msg.sender), token1.balanceOf(msg.sender))
    );

    fees = new uint256[](1);
    fees[0] = 0;
  }

  /// @inheritdoc IKSSmartIntentHook
  function afterExecution(
    bytes32,
    IntentData calldata intentData,
    bytes calldata beforeExecutionData,
    bytes calldata
  ) external view override returns (address[] memory, uint256[] memory, uint256[] memory, address) {
    (
      address pair,
      address token0,
      address token1,
      uint256 liquidityBalanceBefore,
      uint256 liquidity,
      address recipient,
      PackedU128 dstFeesPercent,
      PackedU128 lpValues,
      PackedU128 routerBalancesBefore
    ) = _decodeBeforeExecutionData(beforeExecutionData);

    uint256 balanceAfter = pair.balanceOf(intentData.coreData.mainAddress);
    require(balanceAfter == liquidityBalanceBefore - liquidity, InvalidBalance());

    uint256 amount0 = token0.balanceOf(msg.sender) - routerBalancesBefore.value0();
    uint256 amount1 = token1.balanceOf(msg.sender) - routerBalancesBefore.value1();
    require(amount0 >= lpValues.value0() && amount1 >= lpValues.value1(), InvalidLpValues());

    address[] memory tokens = new address[](2);
    tokens[0] = token0;
    tokens[1] = token1;

    uint256[] memory fees = new uint256[](2);
    fees[0] = amount0 * dstFeesPercent.value0() / PRECISION;
    fees[1] = amount1 * dstFeesPercent.value1() / PRECISION;

    uint256[] memory amounts = new uint256[](2);
    amounts[0] = amount0 - fees[0];
    amounts[1] = amount1 - fees[1];

    return (tokens, fees, amounts, recipient);
  }

  function _decodeHookData(bytes calldata data)
    internal
    pure
    returns (UniswapV2Params calldata validationData)
  {
    assembly ("memory-safe") {
      validationData := add(data.offset, calldataload(data.offset))
    }
  }

  function _decodeHookActionData(bytes calldata data)
    internal
    pure
    virtual
    returns (uint256 index, PackedU128 feesGenerated, PackedU128 dstFeesPercent)
  {
    assembly ("memory-safe") {
      index := calldataload(data.offset)
      feesGenerated := calldataload(add(data.offset, 0x20))
      dstFeesPercent := calldataload(add(data.offset, 0x40))
    }
  }

  function _decodeBeforeExecutionData(bytes calldata data)
    internal
    pure
    virtual
    returns (
      address pair,
      address token0,
      address token1,
      uint256 liquidityBalanceBefore,
      uint256 liquidity,
      address recipient,
      PackedU128 dstFeesPercent,
      PackedU128 lpValues,
      PackedU128 routerBalancesBefore
    )
  {
    assembly ("memory-safe") {
      pair := calldataload(data.offset)
      token0 := calldataload(add(data.offset, 0x20))
      token1 := calldataload(add(data.offset, 0x40))
      liquidityBalanceBefore := calldataload(add(data.offset, 0x60))
      liquidity := calldataload(add(data.offset, 0x80))
      recipient := calldataload(add(data.offset, 0xa0))
      dstFeesPercent := calldataload(add(data.offset, 0xc0))
      lpValues := calldataload(add(data.offset, 0xe0))
      routerBalancesBefore := calldataload(add(data.offset, 0x100))
    }
  }

  function _convertToken1ToToken0(uint256 price, uint256 amount1)
    internal
    pure
    override
    returns (uint256 amount0)
  {
    amount0 = amount1 * price;
  }

  function _calculateLpValues(address pair, uint256 balance0, uint256 balance1, uint256 liquidity)
    internal
    view
    returns (PackedU128 lpValues)
  {
    uint256 totalSupply = IUniswapV2Pair(pair).totalSupply();

    uint256 amount0 = liquidity * balance0 / totalSupply;
    uint256 amount1 = liquidity * balance1 / totalSupply;
    lpValues = toPackedU128(amount0, amount1);
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

  function _buildConditionTree(
    Node[] calldata nodes,
    uint256 fee0Collected,
    uint256 fee1Collected,
    uint256 price
  ) internal pure virtual returns (ConditionTree memory conditionTree) {
    conditionTree.nodes = nodes;
    conditionTree.additionalData = new bytes[](nodes.length);
    for (uint256 i; i < nodes.length; ++i) {
      if (!nodes[i].isLeaf() || nodes[i].condition.isType(TIME_BASED)) {
        continue;
      }
      if (nodes[i].condition.isType(YIELD_BASED)) {
        conditionTree.additionalData[i] = abi.encode(fee0Collected, fee1Collected, price);
      } else if (nodes[i].condition.isType(PRICE_BASED)) {
        conditionTree.additionalData[i] = abi.encode(price);
      }
    }
  }
}
