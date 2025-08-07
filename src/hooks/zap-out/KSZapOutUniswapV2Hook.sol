// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'src/interfaces/uniswapv2/IUniswapV2Pair.sol';

import 'ks-common-sc/src/libraries/token/TokenHelper.sol';
import 'src/hooks/base/BaseHook.sol';

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

  modifier checkTokenLengths(TokenData calldata tokenData) override {
    require(tokenData.erc20Data.length == 1, InvalidTokenData());
    require(tokenData.erc721Data.length == 0, InvalidTokenData());
    require(tokenData.erc1155Data.length == 0, InvalidTokenData());
    _;
  }

  /// @inheritdoc IKSSmartIntentHook
  function beforeExecution(
    bytes32,
    IntentCoreData calldata coreData,
    ActionData calldata actionData
  )
    external
    override
    checkTokenLengths(actionData.tokenData)
    returns (uint256[] memory fees, bytes memory beforeExecutionData)
  {
    uint256 index = abi.decode(actionData.hookActionData, (uint256));

    ZapOutUniswapV2HookData memory zapOutHookData =
      abi.decode(coreData.hookIntentData, (ZapOutUniswapV2HookData));

    ERC20Data[] calldata erc20Data = actionData.tokenData.erc20Data;
    require(erc20Data[0].token == zapOutHookData.srcTokens[index], InvalidTokenData());

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

    fees = new uint256[](actionData.tokenData.erc20Data.length);
    beforeExecutionData = abi.encode(
      zapOutHookData.srcTokens[index],
      zapOutHookData.dstTokens[index],
      erc20Data[0].amount,
      dstBalanceBefore,
      zapOutHookData.minRates[index]
    );
  }

  /// @inheritdoc IKSSmartIntentHook
  function afterExecution(
    bytes32,
    IntentCoreData calldata coreData,
    bytes calldata beforeExecutionData,
    bytes calldata
  ) external view override returns (address[] memory, uint256[] memory, uint256[] memory, address) {
    uint256 minRate;
    uint256 inputAmount;
    uint256 outputAmount;
    ZapOutUniswapV2HookData memory zapOutHookData =
      abi.decode(coreData.hookIntentData, (ZapOutUniswapV2HookData));
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
