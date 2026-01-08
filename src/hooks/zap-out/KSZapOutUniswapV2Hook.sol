// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IKSSmartIntentHook} from '../../interfaces/hooks/IKSSmartIntentHook.sol';
import {IUniswapV2Pair} from '../../interfaces/uniswapv2/IUniswapV2Pair.sol';
import {BaseHook} from '../base/BaseHook.sol';

import {ActionData} from '../../types/ActionData.sol';
import {ERC20Data} from '../../types/ERC20Data.sol';
import {IntentData} from '../../types/IntentData.sol';

import {TokenHelper} from 'ks-common-sc/src/libraries/token/TokenHelper.sol';

contract KSZapOutUniswapV2Hook is BaseHook {
  using TokenHelper for address;

  error InvalidSwapPair();

  error BelowMinRate(uint256 inputAmount, uint256 outputAmount, uint256 minRate);

  error OutsidePriceRange(uint256 priceLower, uint256 priceUpper, uint256 priceCurrent);

  uint256 public constant RATE_DENOMINATOR = 1e18;

  /**
   * @notice Data structure for swap validation
   * @param srcTokens The source tokens
   * @param dstTokens The destination tokens
   * @param priceLowers The lower price bounds, denominated in 1e18
   * @param priceUppers The upper price bounds, denominated in 1e18
   * @param minRates The minimum rates, denominated in 1e18
   * @param recipient
   */
  struct ZapOutUniswapV2HookData {
    address[] srcTokens;
    address[] dstTokens;
    uint256[] priceLowers;
    uint256[] priceUppers;
    uint256[] minRates;
    address recipient;
  }

  modifier checkTokenLengths(ActionData calldata actionData) override {
    require(actionData.erc20Ids.length == 1, InvalidTokenData());
    require(actionData.erc721Ids.length == 0, InvalidTokenData());
    _;
  }

  /// @inheritdoc IKSSmartIntentHook
  function beforeExecution(bytes32, IntentData calldata intentData, ActionData calldata actionData)
    external
    override
    checkTokenLengths(actionData)
    returns (uint256[] memory fees, bytes memory beforeExecutionData)
  {
    uint256 index = abi.decode(actionData.hookActionData, (uint256));

    ZapOutUniswapV2HookData memory zapOutHookData =
      abi.decode(intentData.coreData.hookIntentData, (ZapOutUniswapV2HookData));

    ERC20Data calldata erc20Data = intentData.tokenData.erc20Data[actionData.erc20Ids[0]];
    require(erc20Data.token == zapOutHookData.srcTokens[index], InvalidTokenData());

    uint256 dstBalanceBefore = zapOutHookData.dstTokens[index].balanceOf(zapOutHookData.recipient);

    // this will works for most of UniswapV2 forks
    // as they have different ways to get the reserves
    IUniswapV2Pair(zapOutHookData.srcTokens[index]).skim(zapOutHookData.recipient);
    uint256 priceCurrent;
    {
      address token0 = IUniswapV2Pair(zapOutHookData.srcTokens[index]).token0();
      address token1 = IUniswapV2Pair(zapOutHookData.srcTokens[index]).token1();
      uint256 reserve0 = token0.balanceOf(zapOutHookData.srcTokens[index]);
      uint256 reserve1 = token1.balanceOf(zapOutHookData.srcTokens[index]);
      priceCurrent = (reserve1 * RATE_DENOMINATOR) / reserve0;
    }
    require(
      priceCurrent >= zapOutHookData.priceLowers[index]
        && priceCurrent <= zapOutHookData.priceUppers[index],
      OutsidePriceRange(
        zapOutHookData.priceLowers[index], zapOutHookData.priceUppers[index], priceCurrent
      )
    );

    fees = new uint256[](actionData.erc20Ids.length);
    beforeExecutionData = abi.encode(
      zapOutHookData.srcTokens[index],
      zapOutHookData.dstTokens[index],
      actionData.erc20Amounts[0],
      dstBalanceBefore,
      zapOutHookData.minRates[index]
    );
  }

  /// @inheritdoc IKSSmartIntentHook
  function afterExecution(
    bytes32,
    IntentData calldata intentData,
    bytes calldata beforeExecutionData,
    bytes calldata
  ) external view override returns (address[] memory, uint256[] memory, uint256[] memory, address) {
    uint256 minRate;
    uint256 inputAmount;
    uint256 outputAmount;
    ZapOutUniswapV2HookData memory zapOutHookData =
      abi.decode(intentData.coreData.hookIntentData, (ZapOutUniswapV2HookData));
    {
      address srcToken;
      address dstToken;
      uint256 dstBalanceBefore;
      (srcToken, dstToken, inputAmount, dstBalanceBefore, minRate) =
        abi.decode(beforeExecutionData, (address, address, uint256, uint256, uint256));

      outputAmount = dstToken.balanceOf(zapOutHookData.recipient) - dstBalanceBefore;
    }
    if (outputAmount * RATE_DENOMINATOR < inputAmount * minRate) {
      revert BelowMinRate(inputAmount, outputAmount, minRate);
    }
  }
}
