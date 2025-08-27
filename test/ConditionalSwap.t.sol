// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.t.sol';

import {console} from 'forge-std/console.sol';
import 'src/hooks/swap/KSConditionalSwapHook.sol';

contract ConditionalSwapTest is BaseTest {
  using SafeERC20 for IERC20;
  using TokenHelper for address;

  bytes swapdata =
    hex'00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000007a000000000000000000000000000000000000000000000000000000000000009e000000000000000000000000000000000000000000000000000000000000006e0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec70000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c5990000000000000000000000002e234DAe75C793f67A35089C9d99245E1C58470b0000000000000000000000000000000000000000000000000000000067db987b00000000000000000000000000000000000000000000000000000000000006800000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000040f59b1df7000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000002000000000000000000000000066a9893cc07d91d95644aedd05d03f95e1dba8af000000000000000000000000000000000000000000000000000000003b9aca00000000000000000000000000000000000022d473030f116ddee9f6b43ac78ba3000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000000000002300000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040a9d4c672000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000180000000000000000000000000655edce464cc797526600a462a8154650eee4b77000000000000000000000000000000000000000000000000000000003b9d5f1a000000000000000000000000000000000000000000000000000000003b9d5f1a00000000000000000000000000000000000000000000000006dac07944b594800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca3000000000000005fa94793ea0000001a371930340fc8fbcc09c409c467db9414000000000000000000000000000000000000000000000000000000000000001bdcffd1bf68c2c17dcf00a25c935efba96aa63b7f75dd43d42b3df2cf7273c2260fb4b38a9db829fbfdabcc6262ac3982f1d31366bfde12a7b67f6f31ba52b2cb0000000000000000000000000000000000000000000000000000000000000040d90ce4910000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000001000000000000000000000000007f86bf177dd4f3494b841a37e810a34dd56c829b000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c5990000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000006da929a6bb58cc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000010000000000000000000000000011cbb0000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec70000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c599000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001e000000000000000000000000000000000000000000000000000000000000002000000000000000000000000002e234DAe75C793f67A35089C9d99245E1C58470b000000000000000000000000000000000000000000000000000000003b9aca00000000000000000000000000000000000000000000000000000000000011c7210000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca30000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000003b9aca00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024f7b22536f75726365223a22222c22416d6f756e74496e555344223a22313030302e31373135393231313738353037222c22416d6f756e744f7574555344223a22313030302e34373538333032323939323331222c22526566657272616c223a22222c22466c616773223a302c22416d6f756e744f7574223a2231313636323536222c2254696d657374616d70223a313734323434333436392c22526f7574654944223a2263383438663432632d326465322d343364382d623366372d636637366362666430363536222c22496e74656772697479496e666f223a7b224b65794944223a2231222c225369676e6174757265223a224e39426b4975436430714961362f4d64736635717a61657863436c3754413539426e4d70454741437a74432b5875325176494a36444c34476b7075746b636f627554395657357a42744e427a5463736b4e7768434662372f6f52675173676970424e693878716d323869524b3048496834527a70316457512f437737676a58375168653270313853506966492b7550674e5a34647a5a6a4461686b664d416852796d7765783233714942536a65565a6f44483932596a534b4e546176396f2f2f634754766476336a52555538536841763153464b55514b54515470682f4d4f71534f7370646c37306632714155705274566d7739434b4d383347726164506b55546f5854684a2f6c734e784561634267395a37617a363837394d366d31517538465a687237796374367a4242524a774171464e6646436a364b523969307a4e702f665a2b6876394b6970455341666d5078634e4d67773d3d227d7d0000000000000000000000000000000000';

  uint256 feeBefore;
  uint256 feeAfter;
  uint256 maxSrcFee;
  uint256 maxDstFee;

  uint256 swapAmount = 1_000_000_000;

  KSConditionalSwapHook conditionalSwapHook;
  uint256 currentPrice = 11_662_550_000_000; // USDC/BTC denominated by 1e18

  function setUp() public override {
    super.setUp();

    address[] memory routers = new address[](1);
    routers[0] = address(router);
    deal(tokenOut, address(mockActionContract), 1e30);
    deal(tokenIn, mainAddress, 1e30);

    conditionalSwapHook = new KSConditionalSwapHook(routers);
  }

  function testFuzz_ConditionalSwap(
    uint256 mode,
    uint256 maxFeeBefore,
    uint256 maxFeeAfter,
    uint256 srcFee,
    uint256 dstFee,
    uint256 amountIn,
    uint256 returnAmount
  ) public {
    mode = bound(mode, 0, 2);
    maxSrcFee = bound(maxFeeBefore, 0, 1_000_000);
    maxDstFee = bound(maxFeeAfter, 0, 1_000_000);
    feeBefore = bound(srcFee, 0, 1_000_000);
    feeAfter = bound(dstFee, 0, 1_000_000);

    amountIn = bound(amountIn, 100, 1_000_000e6);
    returnAmount = bound(returnAmount, 100, 1_000_000e8);

    IntentData memory intentData =
      _getIntentData(0, type(uint128).max, 1, new KSConditionalSwapHook.SwapCondition[](0));
    intentData.tokenData.erc20Data[0].amount = amountIn;
    _setUpMainAddress(intentData, false);

    uint256 beforeSwapFee = (amountIn * feeBefore) / 1_000_000;
    uint256 afterSwapFee = (returnAmount * feeAfter) / 1_000_000;

    ActionData memory actionData = _getActionData(
      intentData.tokenData,
      abi.encode(
        tokenIn, tokenOut, amountIn - beforeSwapFee, returnAmount, address(router), mainAddress
      ),
      true
    );

    returnAmount = returnAmount - afterSwapFee;

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    if (feeBefore > maxSrcFee || feeAfter > maxDstFee) {
      vm.expectRevert(
        abi.encodeWithSelector(
          KSConditionalSwapHook.InvalidSwap.selector, feeBefore, feeAfter, maxSrcFee, maxDstFee
        )
      );
      vm.startPrank(caller);
      router.execute(intentData, daSignature, guardian, gdSignature, actionData);
      return;
    }

    uint256[2] memory routerBefore =
      [tokenIn.balanceOf(address(router)), tokenOut.balanceOf(address(router))];
    uint256[2] memory mainAddressBefore =
      [tokenIn.balanceOf(mainAddress), tokenOut.balanceOf(mainAddress)];
    uint256[2] memory feeReceiversBefore =
      [tokenIn.balanceOf(feeRecipient), tokenOut.balanceOf(feeRecipient)];

    vm.startPrank(caller);
    router.execute(intentData, daSignature, guardian, gdSignature, actionData);

    assertEq(tokenIn.balanceOf(address(router)), routerBefore[0]);
    assertEq(tokenOut.balanceOf(address(router)), routerBefore[1]);
    assertEq(tokenIn.balanceOf(mainAddress), mainAddressBefore[0] - amountIn);
    assertEq(tokenOut.balanceOf(mainAddress), mainAddressBefore[1] + returnAmount);
    assertEq(tokenIn.balanceOf(feeRecipient), feeReceiversBefore[0] + beforeSwapFee);
    assertEq(tokenOut.balanceOf(feeRecipient), feeReceiversBefore[1] + afterSwapFee);
  }

  function testConditionalSwapSuccess(uint256 mode) public {
    mode = bound(mode, 0, 2);
    IntentData memory intentData =
      _getIntentData(0, type(uint128).max, 1, new KSConditionalSwapHook.SwapCondition[](0));

    _setUpMainAddress(intentData, false);

    ActionData memory actionData =
      _getActionData(intentData.tokenData, _adjustRecipient(swapdata), false);

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    vm.startPrank(caller);
    router.execute(intentData, daSignature, guardian, gdSignature, actionData);
  }

  function test_DCASwap_TimeBased(uint256 mode) public {
    mode = bound(mode, 0, 2);

    KSConditionalSwapHook.SwapCondition[] memory condition =
      new KSConditionalSwapHook.SwapCondition[](3);

    {
      condition[0] = KSConditionalSwapHook.SwapCondition({
        swapLimit: 1,
        timeLimits: ((block.timestamp - 100) << 128) | (block.timestamp + 100),
        amountInLimits: (swapAmount << 128) | swapAmount,
        maxFees: (0 << 128) | type(uint128).max,
        priceLimits: (0 << 128) | type(uint128).max
      });
      condition[1] = KSConditionalSwapHook.SwapCondition({
        swapLimit: 1,
        timeLimits: ((block.timestamp + 500) << 128) | (block.timestamp + 700),
        amountInLimits: (swapAmount << 128) | swapAmount,
        maxFees: (0 << 128) | type(uint128).max,
        priceLimits: (0 << 128) | type(uint128).max
      });
      condition[2] = KSConditionalSwapHook.SwapCondition({
        swapLimit: 1,
        timeLimits: ((block.timestamp + 1000) << 128) | (block.timestamp + 1200),
        amountInLimits: (swapAmount << 128) | swapAmount,
        maxFees: (0 << 128) | type(uint128).max,
        priceLimits: (0 << 128) | type(uint128).max
      });
    }

    IntentData memory intentData;
    {
      uint256 tmpSwapAmount = swapAmount;
      swapAmount = type(uint256).max;
      intentData = _getIntentData(0, type(uint128).max, 1, condition);
      _setUpMainAddress(intentData, false);
      swapAmount = tmpSwapAmount;
    }
    ActionData memory actionData;
    {
      TokenData memory tokenData;
      tokenData.erc20Data = new ERC20Data[](1);
      tokenData.erc20Data[0] = ERC20Data({token: tokenIn, amount: swapAmount, permitData: ''});
      actionData = _getActionData(
        tokenData,
        abi.encode(
          tokenIn,
          tokenOut,
          swapAmount,
          1000,
          feeAfter == 0 ? mainAddress : address(router),
          mainAddress
        ),
        true
      );
    }

    // swap 1
    {
      _swap(mode, intentData, actionData, 0, 0);
    }

    // swap 2
    {
      vm.warp(block.timestamp + 500);
      actionData.nonce += 1;
      _swap(mode, intentData, actionData, 0, 1);
    }

    // swap 3
    {
      vm.warp(block.timestamp + 1000);
      actionData.nonce += 1;
      _swap(mode, intentData, actionData, 0, 2);
    }
  }

  function test_DCASwap_PriceBased(uint256 mode) public {
    mode = bound(mode, 0, 2);
    KSConditionalSwapHook.SwapCondition[] memory condition =
      new KSConditionalSwapHook.SwapCondition[](1);

    {
      condition[0] = KSConditionalSwapHook.SwapCondition({
        swapLimit: 4,
        timeLimits: (0 << 128) | type(uint128).max,
        amountInLimits: (swapAmount << 128) | swapAmount,
        maxFees: (0 << 128) | type(uint128).max,
        priceLimits: (1_000_000_000_000 - 100 << 128) | (1_000_000_000_000 + 100)
      });
    }

    IntentData memory intentData;
    {
      uint256 tmpSwapAmount = swapAmount;
      swapAmount = type(uint256).max;
      intentData = _getIntentData(0, type(uint128).max, 1, condition);
      _setUpMainAddress(intentData, false);
      swapAmount = tmpSwapAmount;
    }
    ActionData memory actionData;
    {
      TokenData memory tokenData;
      tokenData.erc20Data = new ERC20Data[](1);
      tokenData.erc20Data[0] = ERC20Data({token: tokenIn, amount: swapAmount, permitData: ''});
      actionData = _getActionData(
        tokenData,
        abi.encode(
          tokenIn,
          tokenOut,
          swapAmount,
          1000,
          feeAfter == 0 ? mainAddress : address(router),
          mainAddress
        ),
        true
      );
    }

    // swap 1
    {
      _swap(mode, intentData, actionData, 0, 0);
    }

    // swap 2
    {
      actionData.nonce += 1;
      _swap(mode, intentData, actionData, 1, 0);
    }

    // swap 3
    {
      actionData.nonce += 1;
      _swap(mode, intentData, actionData, 2, 0);
    }
  }

  function _swap(
    uint256 mode,
    IntentData memory intentData,
    ActionData memory actionData,
    uint256 swapCount,
    uint256 index
  ) internal {
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);
    bytes32 hash = router.hashTypedIntentData(intentData);

    uint256 balanceBefore = tokenOut.balanceOf(mainAddress);

    assertEq(conditionalSwapHook.getSwapExecutionCount(hash, 0, index), swapCount);
    vm.startPrank(caller);
    router.execute(intentData, daSignature, guardian, gdSignature, actionData);
    vm.stopPrank();
    assertEq(conditionalSwapHook.getSwapExecutionCount(hash, 0, index), swapCount + 1);

    assertGt(tokenOut.balanceOf(mainAddress), balanceBefore);
  }

  function testRevert_InvalidTimeCondition(uint256 mode) public {
    mode = bound(mode, 0, 2);
    KSConditionalSwapHook.SwapCondition[] memory condition =
      new KSConditionalSwapHook.SwapCondition[](1);

    condition[0] = KSConditionalSwapHook.SwapCondition({
      swapLimit: 1,
      timeLimits: (block.timestamp + 100 << 128) | (block.timestamp + 1000),
      amountInLimits: (0 << 128) | type(uint128).max,
      maxFees: (0 << 128) | type(uint128).max,
      priceLimits: (0 << 128) | type(uint128).max
    });

    IntentData memory intentData = _getIntentData(0, type(uint128).max, 1, condition);
    _setUpMainAddress(intentData, false);

    ActionData memory actionData =
      _getActionData(intentData.tokenData, _adjustRecipient(swapdata), false);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    vm.startPrank(caller);
    vm.expectRevert(KSConditionalSwapHook.InvalidSwap.selector);
    router.execute(intentData, daSignature, guardian, gdSignature, actionData);
  }

  function testRevert_InvalidPriceCondition(uint256 mode) public {
    mode = bound(mode, 0, 2);
    KSConditionalSwapHook.SwapCondition[] memory condition =
      new KSConditionalSwapHook.SwapCondition[](1);

    condition[0] = KSConditionalSwapHook.SwapCondition({
      swapLimit: 1,
      timeLimits: (block.timestamp - 100 << 128) | (block.timestamp + 100),
      amountInLimits: (0 << 128) | type(uint128).max,
      maxFees: (0 << 128) | type(uint128).max,
      priceLimits: (uint256(type(uint128).max) << 128) | type(uint128).max
    });

    IntentData memory intentData = _getIntentData(0, type(uint128).max, 1, condition);

    _setUpMainAddress(intentData, false);

    ActionData memory actionData =
      _getActionData(intentData.tokenData, _adjustRecipient(swapdata), false);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    vm.startPrank(caller);
    vm.expectRevert(KSConditionalSwapHook.InvalidSwap.selector);
    router.execute(intentData, daSignature, guardian, gdSignature, actionData);
  }

  function testRevert_ExceedSwapLimit(uint256 mode) public {
    mode = bound(mode, 0, 2);
    uint256 tmpSwapAmount = swapAmount;
    swapAmount = type(uint256).max;
    IntentData memory intentData =
      _getIntentData(0, type(uint128).max, 1, new KSConditionalSwapHook.SwapCondition[](0));
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
    assertEq(conditionalSwapHook.getSwapExecutionCount(hash, 0, 0), 0);

    {
      (address caller, bytes memory daSignature, bytes memory gdSignature) =
        _getCallerAndSignatures(mode, actionData);

      vm.startPrank(caller);
      router.execute(intentData, daSignature, guardian, gdSignature, actionData);
      actionData.nonce += 1;
      (caller, daSignature, gdSignature) = _getCallerAndSignatures(mode, actionData);
      vm.startPrank(caller);
      vm.expectRevert(KSConditionalSwapHook.InvalidSwap.selector);
      router.execute(intentData, daSignature, guardian, gdSignature, actionData);
    }
    {
      assertEq(conditionalSwapHook.getSwapExecutionCount(hash, 0, 0), 1);
    }
  }

  function testRevert_InvalidTokenIn(uint256 mode) public {
    mode = bound(mode, 0, 2);
    IntentData memory intentData =
      _getIntentData(0, type(uint128).max, 1, new KSConditionalSwapHook.SwapCondition[](0));
    _setUpMainAddress(intentData, false);
    intentData.tokenData.erc20Data[0].token = makeAddr('dummy');
    _setUpMainAddress(intentData, false);

    ActionData memory actionData =
      _getActionData(intentData.tokenData, _adjustRecipient(swapdata), false);

    actionData.tokenData.erc20Data[0].token = makeAddr('dummy');

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        KSConditionalSwapHook.InvalidTokenIn.selector, makeAddr('dummy'), tokenIn
      )
    );
    router.execute(intentData, daSignature, guardian, gdSignature, actionData);
  }

  function testRevert_AmountInTooSmallOrTooLarge(uint256 mode, uint128 min, uint128 max) public {
    mode = bound(mode, 0, 2);
    vm.assume(min < max && (min > swapAmount || max < swapAmount));
    IntentData memory intentData =
      _getIntentData(min, max, 1, new KSConditionalSwapHook.SwapCondition[](0));
    _setUpMainAddress(intentData, false);

    ActionData memory actionData =
      _getActionData(intentData.tokenData, _adjustRecipient(swapdata), false);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    vm.startPrank(caller);
    vm.expectRevert(KSConditionalSwapHook.InvalidSwap.selector);
    router.execute(intentData, daSignature, guardian, gdSignature, actionData);
  }

  function testRevert_ExceedFeeLimit(uint256 mode) public {
    feeBefore = 1000;
    feeAfter = 1000;

    mode = bound(mode, 0, 2);
    IntentData memory intentData =
      _getIntentData(0, type(uint128).max, 1, new KSConditionalSwapHook.SwapCondition[](0));
    _setUpMainAddress(intentData, false);

    uint256 beforeSwapFee = (swapAmount * feeBefore) / 1_000_000;

    ActionData memory actionData = _getActionData(
      intentData.tokenData,
      abi.encode(tokenIn, tokenOut, swapAmount - beforeSwapFee, 1000, address(router), mainAddress),
      true
    );

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    vm.startPrank(caller);
    vm.expectRevert(KSConditionalSwapHook.InvalidSwap.selector);
    router.execute(intentData, daSignature, guardian, gdSignature, actionData);
  }

  function _getActionData(TokenData memory tokenData, bytes memory actionCalldata, bool swapViaMock)
    internal
    view
    returns (ActionData memory actionData)
  {
    uint256 approvalFlags = (1 << (tokenData.erc20Data.length + tokenData.erc721Data.length)) - 1;

    console.log('feeBefore', feeBefore);
    console.log('feeAfter', feeAfter);

    actionData = ActionData({
      tokenData: tokenData,
      approvalFlags: approvalFlags,
      actionSelectorId: swapViaMock ? 0 : 1,
      actionCalldata: swapViaMock
        ? (
          actionCalldata.length == 0
            ? abi.encode(
              tokenIn,
              tokenOut,
              swapAmount,
              1000,
              feeAfter == 0 ? mainAddress : address(router),
              mainAddress
            )
            : actionCalldata
        )
        : actionCalldata,
      hookActionData: abi.encode(0, (feeBefore << 128) | feeAfter),
      extraData: '',
      deadline: block.timestamp + 1 days,
      nonce: 0
    });
  }

  function _getIntentData(
    uint256 min,
    uint256 max,
    uint256 swapLimit,
    KSConditionalSwapHook.SwapCondition[] memory swapConditions
  ) internal view returns (IntentData memory intentData) {
    KSConditionalSwapHook.SwapHookData memory hookData;
    hookData.srcTokens = new address[](1);
    hookData.srcTokens[0] = tokenIn;
    hookData.dstTokens = new address[](1);
    hookData.dstTokens[0] = tokenOut;
    hookData.recipient = mainAddress;
    hookData.swapConditions = new KSConditionalSwapHook.SwapCondition[][](1);

    if (swapConditions.length > 0) {
      hookData.swapConditions[0] = swapConditions;
    } else {
      hookData.swapConditions[0] = new KSConditionalSwapHook.SwapCondition[](1);
      hookData.swapConditions[0][0] = KSConditionalSwapHook.SwapCondition({
        swapLimit: 1,
        timeLimits: (block.timestamp << 128) | (block.timestamp + 1 days),
        amountInLimits: (min << 128) | max,
        maxFees: (maxSrcFee << 128) | maxDstFee,
        priceLimits: (0 << 128) | type(uint128).max
      });
    }

    address[] memory actionContracts = new address[](2);
    actionContracts[0] = address(mockActionContract);
    actionContracts[1] = address(swapRouter);

    bytes4[] memory actionSelectors = new bytes4[](2);
    actionSelectors[0] = MockActionContract.swap.selector;
    actionSelectors[1] = IKSSwapRouterV2.swap.selector;

    IntentCoreData memory coreData = IntentCoreData({
      mainAddress: mainAddress,
      delegatedAddress: delegatedAddress,
      actionContracts: actionContracts,
      actionSelectors: actionSelectors,
      hook: address(conditionalSwapHook),
      hookIntentData: abi.encode(hookData)
    });

    TokenData memory tokenData;
    tokenData.erc20Data = new ERC20Data[](1);
    tokenData.erc20Data[0] = ERC20Data({token: tokenIn, amount: swapAmount, permitData: ''});

    intentData = IntentData({coreData: coreData, tokenData: tokenData, extraData: ''});
  }

  function _setUpMainAddress(IntentData memory intentData, bool withSignedIntent) internal {
    vm.startPrank(mainAddress);
    IERC20(tokenIn).safeIncreaseAllowance(address(router), type(uint256).max);
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

  function _adjustRecipient(bytes memory data) internal view returns (bytes memory) {
    IKSSwapRouterV2.SwapExecutionParams memory params =
      abi.decode(data, (IKSSwapRouterV2.SwapExecutionParams));

    params.desc.dstReceiver = address(router);

    return abi.encode(params);
  }
}
