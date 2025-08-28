// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'src/interfaces/actions/IKSSwapRouterV2.sol';
import 'src/interfaces/actions/IKSSwapRouterV3.sol';

import 'ks-common-sc/src/libraries/token/TokenHelper.sol';
import 'src/hooks/base/BaseHook.sol';

contract KSSwapHook is BaseHook {
  using TokenHelper for address;

  error InvalidSwapPair();

  error BelowMinRate(uint256 inputAmount, uint256 outputAmount, uint256 minRate);

  uint256 public constant RATE_DENOMINATOR = 1e18;

  /**
   * @notice Data structure for swap validation
   * @param srcTokens The source tokens
   * @param dstTokens The destination tokens
   * @param minRates The minimum rates, denominated in 1e18
   * @param recipient
   */
  struct SwapHookData {
    address[] srcTokens;
    address[] dstTokens;
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
    view
    override
    checkTokenLengths(actionData)
    returns (uint256[] memory fees, bytes memory beforeExecutionData)
  {
    uint256 index = abi.decode(actionData.hookActionData, (uint256));

    SwapHookData memory swapHookData =
      abi.decode(intentData.coreData.hookIntentData, (SwapHookData));

    ERC20Data calldata erc20Data = intentData.tokenData.erc20Data[actionData.erc20Ids[0]];
    require(erc20Data.token == swapHookData.srcTokens[index], InvalidTokenData());

    uint256 dstBalanceBefore = swapHookData.dstTokens[index].balanceOf(swapHookData.recipient);

    fees = new uint256[](actionData.erc20Ids.length);
    beforeExecutionData = abi.encode(
      swapHookData.srcTokens[index],
      swapHookData.dstTokens[index],
      actionData.erc20Amounts[0],
      dstBalanceBefore,
      swapHookData.minRates[index]
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
    SwapHookData memory swapHookData =
      abi.decode(intentData.coreData.hookIntentData, (SwapHookData));
    {
      address srcToken;
      address dstToken;
      uint256 dstBalanceBefore;
      (srcToken, dstToken, inputAmount, dstBalanceBefore, minRate) =
        abi.decode(beforeExecutionData, (address, address, uint256, uint256, uint256));

      outputAmount = dstToken.balanceOf(swapHookData.recipient) - dstBalanceBefore;
    }
    if (outputAmount * RATE_DENOMINATOR < inputAmount * minRate) {
      revert BelowMinRate(inputAmount, outputAmount, minRate);
    }
  }
}
