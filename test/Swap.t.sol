// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.t.sol';

contract SwapTest is BaseTest {
  using SafeERC20 for IERC20;

  /// forge-config: default.fuzz.runs = 2
  function testSwapWithRandomCallerSuccess(bool withSignedIntent) public {
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData();

    _setUpMainWallet(intentData, withSignedIntent);

    IKSSessionIntentRouter.ActionData memory actionData =
      _getActionData(intentData.tokenData, swapCalldata);

    bytes memory swSignature = _getSWSignature(actionData);
    bytes memory opSignature = _getOPSignature(actionData);
    vm.warp(block.timestamp + 100);
    vm.startPrank(randomCaller);
    if (withSignedIntent) {
      bytes memory mwSignature = _getMWSignature(intentData);
      router.executeWithSignedIntent(
        intentData, mwSignature, swSignature, operator, opSignature, actionData
      );
    } else {
      router.execute(
        router.hashTypedIntentData(intentData), swSignature, operator, opSignature, actionData
      );
    }
  }

  /// forge-config: default.fuzz.runs = 2
  function testSwapWithOperatorSuccess(bool withSignedIntent) public {
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData();

    _setUpMainWallet(intentData, withSignedIntent);

    IKSSessionIntentRouter.ActionData memory actionData =
      _getActionData(intentData.tokenData, swapCalldata);

    bytes memory swSignature = _getSWSignature(actionData);
    vm.warp(block.timestamp + 100);
    vm.startPrank(operator);
    if (withSignedIntent) {
      bytes memory mwSignature = _getMWSignature(intentData);
      router.executeWithSignedIntent(intentData, mwSignature, swSignature, operator, '', actionData);
    } else {
      router.execute(router.hashTypedIntentData(intentData), swSignature, operator, '', actionData);
    }
  }

  /// forge-config: default.fuzz.runs = 2
  function testSwapWithSessionWalletSuccess(bool withSignedIntent) public {
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData();

    _setUpMainWallet(intentData, withSignedIntent);

    IKSSessionIntentRouter.ActionData memory actionData =
      _getActionData(intentData.tokenData, swapCalldata);

    bytes memory opSignature = _getOPSignature(actionData);
    vm.warp(block.timestamp + 100);
    vm.startPrank(sessionWallet);
    if (withSignedIntent) {
      bytes memory mwSignature = _getMWSignature(intentData);
      router.executeWithSignedIntent(intentData, mwSignature, '', operator, opSignature, actionData);
    } else {
      router.execute(router.hashTypedIntentData(intentData), '', operator, opSignature, actionData);
    }
  }

  function _getIntentData()
    internal
    view
    returns (IKSSessionIntentRouter.IntentData memory intentData)
  {
    KSSwapIntentValidator.SwapValidationData memory validationData;
    validationData.srcTokens = new address[](1);
    validationData.srcTokens[0] = tokenIn;
    validationData.dstTokens = new address[](1);
    validationData.dstTokens[0] = tokenOut;
    validationData.minRates = new uint256[](1);
    validationData.minRates[0] = minRate;

    IKSSessionIntentRouter.IntentCoreData memory coreData = IKSSessionIntentRouter.IntentCoreData({
      mainWallet: mainWallet,
      sessionWallet: sessionWallet,
      startTime: block.timestamp + 10,
      endTime: block.timestamp + 1 days,
      actionContract: swapRouter,
      actionSelector: IKSSwapRouter.swap.selector,
      validator: address(swapValidator),
      validationData: abi.encode(validationData)
    });

    IKSSessionIntentRouter.TokenData memory tokenData;
    tokenData.erc20Data = new IKSSessionIntentRouter.ERC20Data[](1);
    tokenData.erc20Data[0] =
      IKSSessionIntentRouter.ERC20Data({token: tokenIn, amount: amountIn, minRefundAmount: 100});

    intentData = IKSSessionIntentRouter.IntentData({coreData: coreData, tokenData: tokenData});
  }

  function _setUpMainWallet(
    IKSSessionIntentRouter.IntentData memory intentData,
    bool withSignedIntent
  ) internal {
    deal(tokenIn, mainWallet, amountIn);
    vm.startPrank(mainWallet);
    IERC20(tokenIn).safeIncreaseAllowance(address(router), amountIn);
    if (!withSignedIntent) {
      router.delegate(intentData);
    }
    vm.stopPrank();
  }

  function _getActionData(
    IKSSessionIntentRouter.TokenData memory tokenData,
    bytes memory actionCalldata
  ) internal view returns (IKSSessionIntentRouter.ActionData memory actionData) {
    actionData = IKSSessionIntentRouter.ActionData({
      tokenData: tokenData,
      actionCalldata: actionCalldata,
      deadline: block.timestamp + 1 days
    });
  }
}
