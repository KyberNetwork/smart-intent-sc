// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './ConditionalSwapBase.t.sol';

contract ConditionalSwapTest is ConditionalSwapBaseTest {
  using SafeERC20 for IERC20;
  using TokenHelper for address;
  using ArraysHelper for *;
  using MerkleUtils for *;

  bytes constant swapdata =
    hex'00000000000000000000000000000000000000000000000000000000000000200000000000000000000000008f10b468b06c6fd214b65f87778827f7d113f996000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000007c00000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000006f4d7a5c6b52756e795f680b0f7e0c2f21281dde6ef0000000000000000000000003b9aca000000000000000000000000003b9aca00000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000004168e51a2247f49fdf5fd8630675dbaac3742008fce40cc4312ff0cac2add0733d0cd37c1e40f105e5bf69a25449364863be56913f16ea39f2f46d0bf0f0ae61a91b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005e00000000000000000000000001742f7d30605f18f097f356e1eeafdb5e2fde33a00000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000180000000000000000000000000389fd9800000000000000000000000003e95ba800000000000000000000000003b9aca000000000000000000000000000012be7b00000000000000000000000000000000000000000000010000000f42400000000000000000000000000000001111110f0f73c0b2ef09ec012eae758b3e03a9020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000000005c0000000000000000000000000000000000000000000000000000000000000000161f598cd00000000000000007b0e2e8300899b647d5ebc66f9d4fa3f16c540610000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000003a0000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7800000000000000000000000000003e80000000000000000000000003b9aca0000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000220000000000000000000000000000000000000000000000000000000003b9aca003b9d6e0900000000000000015455c918e405a2831fbff8595c0aae35ee3db9d100000000000000000000000000000000000000000000000000000000000000800000000000000000000000008f10b468b06c6fd214b65f87778827f7d113f996000000000000000000000000000000000000000000000000000000000000004000000000000000000000000056534741cd8b152df6d48adf7ac51f75169a83b2000000000000000000000000fff6fbe64b68d618d47c209fe40b0d8ee6e23c90600000000000000000000000000000000000000000000000000000003b9aca003b9d6e0900000000000000015455c918e405a2831fbff8595c0aae35ee3db9d100000000000000000000000000000000000000000000000000000000000000800000000000000000000000008f10b468b06c6fd214b65f87778827f7d113f996000000000000000000000000000000000000000000000000000000000000004000000000000000000000000056534741cd8b152df6d48adf7ac51f75169a83b2000000000000000000000000fff6fbe64b68d618d47c209fe40b0d8ee6e23c90600000000000000000000000000000000000000000000000000000003b9aca00b372966800000000000000015455c918e405a2831fbff8595c0aae35ee3db9d100000000000000000000000000000000000000000000000000000000000000800000000000000000000000008f10b468b06c6fd214b65f87778827f7d113f99600000000000000000000000000000000000000000000000000000000000000200000000300000000000003e8784178d58b641a4febf8d477a6abd285042731320000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c5998000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec70000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c599000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001e000000000000000000000000000000000000000000000000000000000000002000000000000000000000000001742f7d30605f18f097f356e1eeafdb5e2fde33a000000000000000000000000000000000000000000000000000000003b9aca0000000000000000000000000000000000000000000000000000000000000efec80000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000000010000000000000000000000008f10b468b06c6fd214b65f87778827f7d113f9960000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000003b9aca0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b37b22536f75726365223a226b732d736d6172742d696e74656e742d74657374222c22416d6f756e74496e555344223a223939382e333731313134222c22416d6f756e744f7574555344223a223939382e313033393931222c22416d6f756e744f7574223a2231323238343131222c22526f7574654944223a223963623332633732394d70412d4a6a663a62303361623131327233564635704f53222c2254696d657374616d70223a313739323439333330337d00000000000000000000000000';

  function _selectFork() public virtual override {
    vm.createSelectFork('mainnet', 26_233_337);
  }

  struct TestFuzz_ConditionalSwap_Params {
    uint256 mode;
    uint256 maxFeeBefore;
    uint256 maxFeeAfter;
    uint256 srcFee;
    uint256 dstFee;
    uint256 amountIn;
    uint256 returnAmount;
  }

  function testFuzz_ConditionalSwap(TestFuzz_ConditionalSwap_Params memory params) public {
    params.mode = bound(params.mode, 0, 2);
    params.maxFeeBefore = bound(params.maxFeeBefore, 0, 1_000_000);
    params.maxFeeAfter = bound(params.maxFeeAfter, 0, 1_000_000);
    params.srcFee = bound(params.srcFee, 0, 1_000_000);
    params.dstFee = bound(params.dstFee, 0, 1_000_000);
    params.amountIn = bound(params.amountIn, 100, 1_000_000e6);
    params.returnAmount = bound(params.returnAmount, 100, 1_000_000e8);

    IntentData memory intentData =
      _getIntentData(0, type(uint128).max, new KSConditionalSwapHook.SwapCondition[](0));
    intentData.tokenData.erc20Data[0].amount = amountIn;
    _setUpMainAddress(intentData, false);

    uint256 beforeSwapFee = (amountIn * feeBefore) / 1_000_000;
    uint256 afterSwapFee = (params.returnAmount * feeAfter) / 1_000_000;

    ActionData memory actionData = _getActionData(
      intentData.tokenData,
      abi.encode(
        tokenIn,
        tokenOut,
        amountIn - beforeSwapFee,
        params.returnAmount,
        address(router),
        mainAddress
      ),
      true
    );

    params.returnAmount = params.returnAmount - afterSwapFee;

    uint256[2] memory routerBefore =
      [tokenIn.balanceOf(address(router)), tokenOut.balanceOf(address(router))];
    uint256[2] memory mainAddressBefore =
      [tokenIn.balanceOf(mainAddress), tokenOut.balanceOf(mainAddress)];
    uint256[2] memory feeReceiversBefore =
      [tokenIn.balanceOf(partnerRecipient), tokenOut.balanceOf(partnerRecipient)];

    _executeSwap(params.mode, intentData, actionData);

    assertEq(tokenIn.balanceOf(address(router)), routerBefore[0]);
    assertEq(tokenOut.balanceOf(address(router)), routerBefore[1]);
    assertEq(tokenIn.balanceOf(mainAddress), mainAddressBefore[0] - amountIn);
    assertEq(tokenOut.balanceOf(mainAddress), mainAddressBefore[1] + params.returnAmount);
    assertEq(tokenIn.balanceOf(partnerRecipient), feeReceiversBefore[0] + beforeSwapFee);
    assertEq(tokenOut.balanceOf(partnerRecipient), feeReceiversBefore[1] + afterSwapFee);
  }

  function testConditionalSwapSuccess(uint256 mode) public {
    mode = bound(mode, 0, 2);
    IntentData memory intentData =
      _getIntentData(0, type(uint128).max, new KSConditionalSwapHook.SwapCondition[](0));

    _setUpMainAddress(intentData, false);

    ActionData memory actionData = _getActionData(intentData.tokenData, swapdata, false);

    vm.warp(vm.getBlockTimestamp() + 100);
    _executeSwap(mode, intentData, actionData);
  }

  function test_DCASwap_TimeBased(uint256 mode) public {
    mode = bound(mode, 0, 2);

    KSConditionalSwapHook.SwapCondition[] memory condition =
      new KSConditionalSwapHook.SwapCondition[](3);
    condition[0] =
      _timeCondition(toPackedU128(vm.getBlockTimestamp() - 100, vm.getBlockTimestamp() + 100));
    condition[1] =
      _timeCondition(toPackedU128(vm.getBlockTimestamp() + 500, vm.getBlockTimestamp() + 700));
    condition[2] =
      _timeCondition(toPackedU128(vm.getBlockTimestamp() + 1000, vm.getBlockTimestamp() + 1200));

    IntentData memory intentData;
    {
      uint256 tmpSwapAmount = swapAmount;
      swapAmount = type(uint256).max;
      intentData = _getIntentData(0, type(uint128).max, condition);
      _setUpMainAddress(intentData, false);
      swapAmount = tmpSwapAmount;
    }

    ActionData memory actionData = _mockSwapAction();

    _swap(mode, intentData, actionData, 0, 0);

    vm.warp(vm.getBlockTimestamp() + 500);
    actionData.nonce += 1;
    _swap(mode, intentData, actionData, 0, 1);

    vm.warp(vm.getBlockTimestamp() + 600);
    actionData.nonce += 1;
    _swap(mode, intentData, actionData, 0, 2);
  }

  function test_DCASwap_PriceBased(uint256 mode) public {
    mode = bound(mode, 0, 2);
    KSConditionalSwapHook.SwapCondition[] memory condition =
      new KSConditionalSwapHook.SwapCondition[](1);
    condition[0] = KSConditionalSwapHook.SwapCondition({
      swapLimit: 4,
      timeLimits: toPackedU128(0, type(uint128).max),
      amountInLimits: toPackedU128(swapAmount, swapAmount),
      maxFees: toPackedU128(0, type(uint128).max),
      minPrice: (1_000_000_000_000 - 100) * 1e18,
      maxPrice: (1_000_000_000_000 + 100) * 1e18,
      oracle: _noOracle()
    });

    IntentData memory intentData;
    {
      uint256 tmpSwapAmount = swapAmount;
      swapAmount = type(uint256).max;
      intentData = _getIntentData(0, type(uint128).max, condition);
      _setUpMainAddress(intentData, false);
      swapAmount = tmpSwapAmount;
    }
    ActionData memory actionData = _mockSwapAction();

    _swap(mode, intentData, actionData, 0, 0);
    actionData.nonce += 1;
    _swap(mode, intentData, actionData, 1, 0);
    actionData.nonce += 1;
    _swap(mode, intentData, actionData, 2, 0);
  }

  function testRevert_InvalidTimeCondition(uint256 mode) public {
    mode = bound(mode, 0, 2);
    KSConditionalSwapHook.SwapCondition[] memory condition =
      new KSConditionalSwapHook.SwapCondition[](1);
    condition[0] =
      _timeCondition(toPackedU128(vm.getBlockTimestamp() + 100, vm.getBlockTimestamp() + 1000));

    IntentData memory intentData = _getIntentData(0, type(uint128).max, condition);
    _setUpMainAddress(intentData, false);

    ActionData memory actionData = _getActionData(intentData.tokenData, swapdata, false);

    _expectExecuteRevert(
      mode, intentData, actionData, KSConditionalSwapHook.InvalidSwapTime.selector
    );
  }

  function testRevert_InvalidPriceCondition(uint256 mode) public {
    mode = bound(mode, 0, 2);
    KSConditionalSwapHook.SwapCondition[] memory condition =
      new KSConditionalSwapHook.SwapCondition[](1);
    condition[0] = KSConditionalSwapHook.SwapCondition({
      swapLimit: 1,
      timeLimits: toPackedU128(vm.getBlockTimestamp() - 100, vm.getBlockTimestamp() + 100),
      amountInLimits: toPackedU128(0, type(uint128).max),
      maxFees: toPackedU128(0, type(uint128).max),
      minPrice: type(uint256).max,
      maxPrice: type(uint256).max,
      oracle: _noOracle()
    });

    IntentData memory intentData = _getIntentData(0, type(uint128).max, condition);
    _setUpMainAddress(intentData, false);

    ActionData memory actionData = _getActionData(intentData.tokenData, swapdata, false);

    _expectExecuteRevert(
      mode, intentData, actionData, KSConditionalSwapHook.InvalidSwapPrice.selector
    );
  }

  function testRevert_ExceedSwapLimit(uint256 mode) public {
    mode = bound(mode, 0, 2);
    uint256 tmpSwapAmount = swapAmount;
    swapAmount = type(uint256).max;
    IntentData memory intentData =
      _getIntentData(0, type(uint128).max, new KSConditionalSwapHook.SwapCondition[](0));
    _setUpMainAddress(intentData, false);
    swapAmount = tmpSwapAmount;
    ActionData memory actionData;
    {
      TokenData memory tokenData;
      tokenData.erc20Data = new ERC20Data[](1);
      tokenData.erc20Data[0] = ERC20Data({token: tokenIn, amount: swapAmount, permitData: ''});
      actionData = _getActionData(tokenData, '', true);
    }

    bytes32 hash = router.hashTypedIntentData(intentData);
    assertEq(conditionalSwapHook.getSwapExecutionCount(hash, 0), 0);

    _executeSwap(mode, intentData, actionData);
    actionData.nonce += 1;
    _expectExecuteRevert(
      mode, intentData, actionData, KSConditionalSwapHook.SwapLimitExceeded.selector
    );

    assertEq(conditionalSwapHook.getSwapExecutionCount(hash, 0), 1);
  }

  /// @dev tokenIn is read from the intent and hashed into the leaf, so a token the holder never
  ///      committed to fails the proof rather than a dedicated tokenIn check.
  function testRevert_InvalidTokenIn(uint256 mode) public {
    mode = bound(mode, 0, 2);
    IntentData memory intentData =
      _getIntentData(0, type(uint128).max, new KSConditionalSwapHook.SwapCondition[](0));
    _setUpMainAddress(intentData, false);
    intentData.tokenData.erc20Data[0].token = makeAddr('dummy');
    _setUpMainAddress(intentData, false);

    ActionData memory actionData = _getActionData(intentData.tokenData, swapdata, false);
    actionData.erc20Ids[0] = 0;

    _expectExecuteRevert(mode, intentData, actionData, KSConditionalSwapHook.InvalidProof.selector);
  }

  function testRevert_AmountInTooSmallOrTooLarge(uint256 mode, uint128 min, uint128 max) public {
    mode = bound(mode, 0, 2);
    vm.assume(min < max && (min > swapAmount || max < swapAmount));
    IntentData memory intentData =
      _getIntentData(min, max, new KSConditionalSwapHook.SwapCondition[](0));
    _setUpMainAddress(intentData, false);

    ActionData memory actionData = _getActionData(intentData.tokenData, swapdata, false);

    _expectExecuteRevert(
      mode, intentData, actionData, KSConditionalSwapHook.InvalidSwapAmountIn.selector
    );
  }

  function testRevert_ExceedFeeLimit(uint256 mode) public {
    feeBefore = 1000;
    feeAfter = 1000;

    mode = bound(mode, 0, 2);
    IntentData memory intentData =
      _getIntentData(0, type(uint128).max, new KSConditionalSwapHook.SwapCondition[](0));
    _setUpMainAddress(intentData, false);

    uint256 beforeSwapFee = (swapAmount * feeBefore) / 1_000_000;

    ActionData memory actionData = _getActionData(
      intentData.tokenData,
      abi.encode(tokenIn, tokenOut, swapAmount - beforeSwapFee, 1000, address(router), mainAddress),
      true
    );

    _expectExecuteRevert(
      mode, intentData, actionData, KSConditionalSwapHook.InvalidSwapFee.selector
    );
  }

  function testRevert_InvalidProof(uint256 mode) public {
    mode = bound(mode, 0, 2);
    IntentData memory intentData =
      _getIntentData(0, type(uint128).max, new KSConditionalSwapHook.SwapCondition[](0));
    _setUpMainAddress(intentData, false);

    uint256 beforeSwapFee = (swapAmount * feeBefore) / 1_000_000;
    ActionData memory actionData = _getActionData(
      intentData.tokenData,
      abi.encode(tokenIn, tokenOut, swapAmount - beforeSwapFee, 1000, address(router), mainAddress),
      true
    );

    // prove the committed leaf 0 but claim it is leaf 1, so the recomputed leaf misses the root
    bytes32[] memory memLeaves = leaves;
    actionData.hookActionData = abi.encode(
      MerkleUtils.getProof(memLeaves, 0),
      uint256(1),
      tokenOut,
      toPackedU128(feeBefore, feeAfter),
      leafConditions[0]
    );

    _expectExecuteRevert(mode, intentData, actionData, KSConditionalSwapHook.InvalidProof.selector);
  }

  /// @dev swap counts are packed into a byte per index, so a leaf index past uint8 has nowhere to
  ///      be recorded and must be rejected rather than silently aliasing another index.
  function testRevert_InvalidLeafIndex(uint256 mode) public {
    mode = bound(mode, 0, 2);
    uint256 overflowLeafIndex = uint256(type(uint8).max) + 1;

    KSConditionalSwapHook.SwapCondition[] memory conditions =
      new KSConditionalSwapHook.SwapCondition[](1);
    conditions[0] = KSConditionalSwapHook.SwapCondition({
      swapLimit: 1,
      timeLimits: toPackedU128(vm.getBlockTimestamp(), vm.getBlockTimestamp() + 1 days),
      amountInLimits: toPackedU128(0, type(uint128).max),
      maxFees: toPackedU128(maxSrcFee, maxDstFee),
      minPrice: 0,
      maxPrice: type(uint256).max,
      oracle: _noOracle()
    });

    // commit the condition at the overflowing index, so the proof itself is valid
    _setUpLeaves([overflowLeafIndex].toMemoryArray(), conditions);
    IntentData memory intentData = _getIntentDataForRoot();
    _setUpMainAddress(intentData, false);

    ActionData memory actionData = _getActionData(intentData.tokenData, '', true);
    bytes32[] memory memLeaves = leaves;
    actionData.hookActionData = abi.encode(
      MerkleUtils.getProof(memLeaves, 0),
      overflowLeafIndex,
      tokenOut,
      toPackedU128(feeBefore, feeAfter),
      conditions[0]
    );

    _expectExecuteRevert(
      mode, intentData, actionData, KSConditionalSwapHook.InvalidLeafIndex.selector
    );
  }
}
