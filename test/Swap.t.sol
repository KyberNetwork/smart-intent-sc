// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.t.sol';

contract SwapTest is BaseTest {
  using SafeERC20 for IERC20;

  function setUp() public override {
    super.setUp();

    recipient = 0xA9B8506c28EAa9bD51D1fF5D42047611e481a392;
  }

  /// forge-config: default.fuzz.runs = 10
  function testSwapSuccess(uint256 mode) public {
    mode = bound(mode, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData();

    _setUpMainAddress(intentData, false);

    IKSSessionIntentRouter.ActionData memory actionData =
      _getActionData(intentData.tokenData, swapCalldata);

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    vm.startPrank(caller);
    router.execute(
      router.hashTypedIntentData(intentData), daSignature, guardian, gdSignature, actionData
    );
  }

  /// forge-config: default.fuzz.runs = 10
  function testSwapWithSignedIntentSuccess(uint256 mode) public {
    mode = bound(mode, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData();

    _setUpMainAddress(intentData, true);

    IKSSessionIntentRouter.ActionData memory actionData =
      _getActionData(intentData.tokenData, swapCalldata);

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    bytes memory maSignature = _getMASignature(intentData);
    vm.startPrank(caller);
    router.executeWithSignedIntent(
      intentData, maSignature, daSignature, guardian, gdSignature, actionData
    );
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
    validationData.recipient = recipient;

    IKSSessionIntentRouter.IntentCoreData memory coreData = IKSSessionIntentRouter.IntentCoreData({
      mainAddress: mainAddress,
      delegatedAddress: delegatedAddress,
      startTime: block.timestamp + 10,
      endTime: block.timestamp + 1 days,
      actionContracts: _toArray(swapRouter),
      actionSelectors: _toArray(IKSSwapRouter.swap.selector),
      validator: address(swapValidator),
      validationData: abi.encode(validationData)
    });

    IKSSessionIntentRouter.TokenData memory tokenData;
    tokenData.erc20Data = new IKSSessionIntentRouter.ERC20Data[](1);
    tokenData.erc20Data[0] = IKSSessionIntentRouter.ERC20Data({token: tokenIn, amount: amountIn});

    intentData =
      IKSSessionIntentRouter.IntentData({coreData: coreData, tokenData: tokenData, extraData: ''});
  }

  function _setUpMainAddress(
    IKSSessionIntentRouter.IntentData memory intentData,
    bool withSignedIntent
  ) internal {
    deal(tokenIn, mainAddress, amountIn);
    vm.startPrank(mainAddress);
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
      actionSelectorId: 0,
      actionCalldata: actionCalldata,
      validatorData: abi.encode(0),
      extraData: '',
      deadline: block.timestamp + 1 days
    });
  }
}
