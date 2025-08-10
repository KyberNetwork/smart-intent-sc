// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.t.sol';

import 'src/hooks/swap/KSSwapHook.sol';

contract SwapTest is BaseTest {
  using SafeERC20 for IERC20;

  KSSwapHook swapHook;

  function setUp() public override {
    super.setUp();

    recipient = 0xA9B8506c28EAa9bD51D1fF5D42047611e481a392;

    swapHook = new KSSwapHook();
  }

  /// forge-config: default.fuzz.runs = 10
  function testSwapSuccess(uint256 mode) public {
    mode = bound(mode, 0, 2);
    IntentData memory intentData = _getIntentData();

    _setUpMainAddress(intentData, false);

    ActionData memory actionData = _getActionData(intentData.tokenData, swapCalldata);

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    vm.startPrank(caller);
    router.execute(intentData, daSignature, guardian, gdSignature, actionData);
  }

  /// forge-config: default.fuzz.runs = 10
  function testSwapWithSignedIntentSuccess(uint256 mode) public {
    mode = bound(mode, 0, 2);
    IntentData memory intentData = _getIntentData();

    _setUpMainAddress(intentData, true);

    ActionData memory actionData = _getActionData(intentData.tokenData, swapCalldata);

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    bytes memory maSignature = _getMASignature(intentData);
    vm.startPrank(caller);
    router.executeWithSignedIntent(
      intentData, maSignature, daSignature, guardian, gdSignature, actionData
    );
  }

  function _getIntentData() internal view returns (IntentData memory intentData) {
    KSSwapHook.SwapHookData memory hookData;
    hookData.srcTokens = new address[](1);
    hookData.srcTokens[0] = tokenIn;
    hookData.dstTokens = new address[](1);
    hookData.dstTokens[0] = tokenOut;
    hookData.minRates = new uint256[](1);
    hookData.minRates[0] = minRate;
    hookData.recipient = recipient;

    IntentCoreData memory coreData = IntentCoreData({
      mainAddress: mainAddress,
      delegatedAddress: delegatedAddress,
      actionContracts: _toArray(swapRouter),
      actionSelectors: _toArray(IKSSwapRouterV2.swap.selector),
      hook: address(swapHook),
      hookIntentData: abi.encode(hookData)
    });

    TokenData memory tokenData;
    tokenData.erc20Data = new ERC20Data[](1);
    tokenData.erc20Data[0] = ERC20Data({token: tokenIn, amount: amountIn, permitData: ''});

    intentData = IntentData({coreData: coreData, tokenData: tokenData, extraData: ''});
  }

  function _setUpMainAddress(IntentData memory intentData, bool withSignedIntent) internal {
    deal(tokenIn, mainAddress, amountIn);
    vm.startPrank(mainAddress);
    IERC20(tokenIn).safeIncreaseAllowance(address(router), amountIn);
    if (!withSignedIntent) {
      router.delegate(intentData);
    }
    vm.stopPrank();
  }

  function _getActionData(TokenData memory tokenData, bytes memory actionCalldata)
    internal
    view
    returns (ActionData memory actionData)
  {
    uint256 approvalFlags = (1 << (tokenData.erc20Data.length + tokenData.erc721Data.length)) - 1;

    actionData = ActionData({
      tokenData: tokenData,
      approvalFlags: approvalFlags,
      actionSelectorId: 0,
      actionCalldata: actionCalldata,
      hookActionData: abi.encode(0),
      extraData: '',
      deadline: block.timestamp + 1 days,
      nonce: 0
    });
  }
}
