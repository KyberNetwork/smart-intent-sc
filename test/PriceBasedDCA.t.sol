// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.t.sol';
import 'src/validators/KSPriceBasedDCAIntentValidator.sol';

contract PriceBasedDCATest is BaseTest {
  using SafeERC20 for IERC20;

  struct Swap {
    bytes data;
    bytes32 selectorAndFlags; // [selector (32 bits) + flags (224 bits)]; selector is 4 most significant bytes; flags are stored in 4 least significant bytes.
  }

  struct SwapExecutorDescription {
    Swap[][] swapSequences;
    address tokenIn;
    address tokenOut;
    address to;
    uint256 deadline;
    bytes positiveSlippageData;
  }

  address private constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

  KSPriceBasedDCAIntentValidator dcaValidator;

  uint256 actualAmountOut = 93_365_783_355_232_154_369_729;
  uint32 firstTimestamp = 1_742_449_139;

  uint32[] timestamps = [firstTimestamp, firstTimestamp + 1 days, firstTimestamp + 2 days];
  uint256[] amountIns = [1e9, 1e9, 1e9];
  uint256[] amountOutLimits = [7e22 << 128 | 1e23, 8e22 << 128 | 1e23, 9e22 << 128 | 1e23];
  uint256 swap;
  uint32 deadline;
  uint256 minAmountOut;
  uint256 nonce = 0;

  function setUp() public override {
    super.setUp();

    address[] memory initialRouters = new address[](1);
    initialRouters[0] = address(router);
    dcaValidator = new KSPriceBasedDCAIntentValidator(initialRouters);

    address[] memory validators = new address[](1);
    validators[0] = address(dcaValidator);
    vm.prank(owner);
    router.whitelistValidators(validators, true);

    tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    tokenOut = 0x0bBCEfA5F3630Cae34842cb9D9b36BC0d4257a0d;

    swapCalldata =
      hex'00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000005c000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000000bbcefa5f3630cae34842cb9d9b36bc0d4257a0d000000000000000000000000318d280c0dc7c0a3b4f03372f54c07d923c08dda0000000000000000000000000000000000000000000000000000000067dbae860000000000000000000000000000000000000000000000000000000000000460000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000040f59b1df7000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000002000000000000000000000000066a9893cc07d91d95644aedd05d03f95e1dba8af000000000000000000000000000000000000000000000000000000003b9aca00000000000000000000000000000000000022d473030f116ddee9f6b43ac78ba3000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001f4000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004063407a490000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca30000000000000000000000004099da217c2c9ee5a603fb2f209a0beaac6858ca000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000bbcefa5f3630cae34842cb9d9b36bc0d4257a0d00000000000000000000000000000000000000000000000006e0f6ae992bfca200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000000000000000000000014d6d5f7c30fe7500000000000013dfb2263cc296b888da0000000000000000000000004f82e73edb06d29ff62c91ec8f5ff06571bdeb29000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000000bbcefa5f3630cae34842cb9d9b36bc0d4257a0d000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000318d280c0dc7c0a3b4f03372f54c07d923c08dda000000000000000000000000000000000000000000000000000000003b9aca000000000000000000000000000000000000000000000013c641e60bd0f9cea6e30000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca30000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000003b9aca0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002667b22536f75726365223a226b7962657273776170222c22416d6f756e74496e555344223a223939392e35393438333533333834333233222c22416d6f756e744f7574555344223a223939352e32333337393137323434333132222c22526566657272616c223a22222c22466c616773223a302c22416d6f756e744f7574223a223933383531343234313137353534383035323436313730222c2254696d657374616d70223a313734323434393130392c22526f7574654944223a2263643334353132352d313430612d343631652d383938302d626133656261643265346435222c22496e74656772697479496e666f223a7b224b65794944223a2231222c225369676e6174757265223a224c7a6a70734e444d6334336334574f39594e754b6e67373768455a36545a4755575431614155486b7a4764504877473347764f6c5859306e4e436658306972686463616e465135337843535a62425047624743374462457869523449464a624b4c78716d744a366455585933395a5436466836365162505a4f786c77787a6555746550304f7946622b51587379396d44596d39336168355a7063386c64704c796165526e5153444b49717651436a335452435275794c4e70517534376f75626f52544c553152532b51736a4e50633430436c6d4f6a55396b736a6a492f416361733352434d565a3564745058446149744639732f71516b334b354f7a34775450672b53514334734d4b50424134614c79392f39355a716353364738514d7350734453466a596a516f51677a302b464e6e4f77384754772b7356416f414a4f46715873346b6145463437486e463967536c7049355675413d3d227d7d0000000000000000000000000000000000000000000000000000';
  }

  function test_priceBasedSuccess(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);

    for (uint256 i; i < timestamps.length; i++) {
      uint32 executionTime = timestamps[i];
      deadline = timestamps[i] + 10;
      swap = i;
      minAmountOut = amountOutLimits[i] >> 128;
      swapCalldata = _adjustMinReturnAmount(swapCalldata);

      IKSSessionIntentRouter.IntentData memory intentData = _getIntentData();

      _setUpMainAddress(intentData, false);

      IKSSessionIntentRouter.ActionData memory actionData =
        _getActionData(intentData.tokenData, _adjustDeadline(swapCalldata));

      vm.warp(executionTime);
      (address caller, bytes memory daSignature, bytes memory gdSignature) =
        _getCallerAndSignatures(mode, actionData);

      vm.startPrank(caller);
      router.execute(
        router.hashTypedIntentData(intentData), daSignature, guardian, gdSignature, actionData
      );
      vm.stopPrank();
    }
  }

  function test_skipSwap(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    uint256 swapNo = bound(seed, 0, timestamps.length);

    for (uint256 i; i < timestamps.length; i++) {
      //skip a swap, but other swaps still executed
      if (i == swapNo) {
        continue;
      }

      uint32 executionTime = timestamps[i];
      deadline = timestamps[i] + 10;
      swap = i;
      minAmountOut = amountOutLimits[i] >> 128;
      swapCalldata = _adjustMinReturnAmount(swapCalldata);

      IKSSessionIntentRouter.IntentData memory intentData = _getIntentData();

      _setUpMainAddress(intentData, false);

      IKSSessionIntentRouter.ActionData memory actionData =
        _getActionData(intentData.tokenData, _adjustDeadline(swapCalldata));

      vm.warp(executionTime);
      (address caller, bytes memory daSignature, bytes memory gdSignature) =
        _getCallerAndSignatures(mode, actionData);

      vm.startPrank(caller);
      router.execute(
        router.hashTypedIntentData(intentData), daSignature, guardian, gdSignature, actionData
      );
      vm.stopPrank();
    }
  }

  function test_nativeOut(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);

    tokenOut = ETH_ADDRESS;
    actualAmountOut = 493_606_057_603_605_781;

    delete amountOutLimits;
    amountOutLimits.push(46e16 << 128 | 50e16);
    amountOutLimits.push(47e16 << 128 | 50e16);
    amountOutLimits.push(48e16 << 128 | 50e16);

    recipient = 0xdeAD00000000000000000000000000000000dEAd;
    swapCalldata =
      hex'00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000003a000000000000000000000000000000000000000000000000000000000000005e000000000000000000000000000000000000000000000000000000000000002e0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000dead00000000000000000000000000000000dead00000000000000000000000000000000000000000000000000000000773593ff00000000000000000000000000000000000000000000000000000000000002800000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004063407a490000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca3000000000000000000000000e0554a476a092703abdb3ef35c80e0d76d32939f000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000000000003b9aca0000000000000000000000000000000000000000000000000000000001000276a4000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000805bdac33e000000000000000007a69996cdae59a1000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000dead00000000000000000000000000000000dead000000000000000000000000000000000000000000000000000000003b9aca00000000000000000000000000000000000000000000000000061f136952cc8c0f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca30000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000003b9aca0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002777b22536f75726365223a226b79626572737761702d6c696d69742d6f726465722d6f70657261746f72222c22416d6f756e74496e555344223a223939392e39383437303732373431383936222c22416d6f756e744f7574555344223a22313030302e32353736343334373334393935222c22526566657272616c223a22222c22466c616773223a302c22416d6f756e744f7574223a22353531323936383737333734333634303634222c2254696d657374616d70223a313734333636343533392c22526f7574654944223a2263633163303061652d313063332d346665632d383234632d336266646132373261663339222c22496e74656772697479496e666f223a7b224b65794944223a2231222c225369676e6174757265223a2256503149333948335755702b49794e53706f456e6842385758734b304f4a774946306c3671573874446959346a484f324e4345662b2b44435832326e2b335a5132594a3650734c4d375a4162335872366144543257553969356d366b51624f71743639502f7a4954387574725731434b58724577417534754e6e32753251557179527a786131526b632b63534e314b335a513835696f41346c5058726a313863466176354c5559533679315347487a334e672f4e332f304d6964646770616d622f416c5344412b37507055475673305872716d6d51656d753666553272644c4836346b4645536d5074387a5a316a3554674e397a5432376c4957766e51552f524645526164314a427634723556374f62434d6b73726e58346374465535756835474b45455152475a776f346177302f476b39776b6c78726446315a676e5371556d645072545635457469687a666842336242714d57513d3d227d7d000000000000000000';

    for (uint256 i; i < timestamps.length; i++) {
      uint32 executionTime = timestamps[i];
      deadline = timestamps[i] + 10;
      swap = i;

      IKSSessionIntentRouter.IntentData memory intentData = _getIntentData();

      _setUpMainAddress(intentData, false);

      IKSSessionIntentRouter.ActionData memory actionData =
        _getActionData(intentData.tokenData, _adjustDeadline(swapCalldata));

      vm.warp(executionTime);
      (address caller, bytes memory daSignature, bytes memory gdSignature) =
        _getCallerAndSignatures(mode, actionData);

      vm.startPrank(caller);
      router.execute(
        router.hashTypedIntentData(intentData), daSignature, guardian, gdSignature, actionData
      );
      vm.stopPrank();
    }
  }

  function test_exceedNumSwaps(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);

    uint256 numSwaps = timestamps.length;
    timestamps.push(firstTimestamp + 3 days);

    for (uint256 i; i < timestamps.length; i++) {
      uint32 executionTime = timestamps[i];
      deadline = timestamps[i] + 10;
      swap = i;
      minAmountOut = 9e22;
      swapCalldata = _adjustMinReturnAmount(swapCalldata);

      IKSSessionIntentRouter.IntentData memory intentData = _getIntentData();

      _setUpMainAddress(intentData, false);

      IKSSessionIntentRouter.ActionData memory actionData =
        _getActionData(intentData.tokenData, _adjustDeadline(swapCalldata));

      vm.warp(executionTime);
      (address caller, bytes memory daSignature, bytes memory gdSignature) =
        _getCallerAndSignatures(mode, actionData);

      bytes32 intentHash = router.hashTypedIntentData(intentData);

      vm.startPrank(caller);
      if (i == timestamps.length - 1) {
        vm.expectRevert(
          abi.encodeWithSelector(
            KSPriceBasedDCAIntentValidator.ExceedNumSwaps.selector, numSwaps, i
          )
        );
      }

      router.execute(intentHash, daSignature, guardian, gdSignature, actionData);
      vm.stopPrank();
    }
  }

  function test_invalidTokenIn(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);

    for (uint256 i; i < timestamps.length; i++) {
      uint32 executionTime = timestamps[i];
      deadline = executionTime + 10;
      swap = i;
      minAmountOut = 9e22;
      swapCalldata = _adjustMinReturnAmount(swapCalldata);

      IKSSessionIntentRouter.IntentData memory intentData = _getIntentData();
      KSPriceBasedDCAIntentValidator.DCAValidationData memory validationData = abi.decode(
        intentData.coreData.validationData, (KSPriceBasedDCAIntentValidator.DCAValidationData)
      );
      validationData.srcToken = makeAddr('dummy'); //invalid tokenIn
      intentData.coreData.validationData = abi.encode(validationData);

      _setUpMainAddress(intentData, false);

      IKSSessionIntentRouter.ActionData memory actionData =
        _getActionData(intentData.tokenData, _adjustDeadline(swapCalldata));

      vm.warp(executionTime);
      (address caller, bytes memory daSignature, bytes memory gdSignature) =
        _getCallerAndSignatures(mode, actionData);

      bytes32 intentHash = router.hashTypedIntentData(intentData);

      vm.startPrank(caller);
      vm.expectRevert(
        abi.encodeWithSelector(
          KSPriceBasedDCAIntentValidator.InvalidTokenIn.selector, validationData.srcToken, tokenIn
        )
      );
      router.execute(intentHash, daSignature, guardian, gdSignature, actionData);
      vm.stopPrank();
    }
  }

  function test_invalidAmountIn(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);

    for (uint256 i; i < timestamps.length; i++) {
      uint32 executionTime = timestamps[i];
      deadline = executionTime + 10;
      swap = i;
      minAmountOut = 9e22;
      swapCalldata = _adjustMinReturnAmount(swapCalldata);

      IKSSessionIntentRouter.IntentData memory intentData = _getIntentData();
      KSPriceBasedDCAIntentValidator.DCAValidationData memory validationData = abi.decode(
        intentData.coreData.validationData, (KSPriceBasedDCAIntentValidator.DCAValidationData)
      );
      validationData.amountIns[0] = 1e8; //invalid amountIn
      validationData.amountIns[1] = 1e8; //invalid amountIn
      validationData.amountIns[2] = 1e8; //invalid amountIn

      intentData.coreData.validationData = abi.encode(validationData);

      _setUpMainAddress(intentData, false);

      IKSSessionIntentRouter.ActionData memory actionData =
        _getActionData(intentData.tokenData, _adjustDeadline(swapCalldata));

      vm.warp(executionTime);
      (address caller, bytes memory daSignature, bytes memory gdSignature) =
        _getCallerAndSignatures(mode, actionData);

      bytes32 intentHash = router.hashTypedIntentData(intentData);

      vm.startPrank(caller);
      vm.expectRevert(
        abi.encodeWithSelector(
          KSPriceBasedDCAIntentValidator.InvalidAmountIn.selector, 1e8, amountIn
        )
      );
      router.execute(intentHash, daSignature, guardian, gdSignature, actionData);
      vm.stopPrank();
    }
  }

  function test_invalidAmountOut_min(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);

    for (uint256 i; i < timestamps.length; i++) {
      uint32 executionTime = timestamps[i];
      deadline = executionTime + 10;
      swap = i;
      minAmountOut = 9e22;
      swapCalldata = _adjustMinReturnAmount(swapCalldata);

      IKSSessionIntentRouter.IntentData memory intentData = _getIntentData();
      KSPriceBasedDCAIntentValidator.DCAValidationData memory validationData = abi.decode(
        intentData.coreData.validationData, (KSPriceBasedDCAIntentValidator.DCAValidationData)
      );
      validationData.amountOutLimits[0] = actualAmountOut + 1 << 128 | 1e23; //invalid amountOut
      validationData.amountOutLimits[1] = actualAmountOut + 1 << 128 | 1e23; //invalid amountOut
      validationData.amountOutLimits[2] = actualAmountOut + 1 << 128 | 1e23; //invalid amountOut
      intentData.coreData.validationData = abi.encode(validationData);

      _setUpMainAddress(intentData, false);

      IKSSessionIntentRouter.ActionData memory actionData =
        _getActionData(intentData.tokenData, _adjustDeadline(swapCalldata));

      vm.warp(executionTime);
      (address caller, bytes memory daSignature, bytes memory gdSignature) =
        _getCallerAndSignatures(mode, actionData);

      bytes32 intentHash = router.hashTypedIntentData(intentData);

      vm.startPrank(caller);
      vm.expectRevert(
        abi.encodeWithSelector(
          KSPriceBasedDCAIntentValidator.InvalidAmountOut.selector,
          actualAmountOut + 1,
          1e23,
          actualAmountOut
        )
      );
      router.execute(intentHash, daSignature, guardian, gdSignature, actionData);
      vm.stopPrank();
    }
  }

  function test_invalidAmountOut_max(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);

    for (uint256 i; i < timestamps.length; i++) {
      uint32 executionTime = timestamps[i];
      deadline = executionTime + 10;
      swap = i;
      minAmountOut = 9e22;
      swapCalldata = _adjustMinReturnAmount(swapCalldata);

      IKSSessionIntentRouter.IntentData memory intentData = _getIntentData();
      KSPriceBasedDCAIntentValidator.DCAValidationData memory validationData = abi.decode(
        intentData.coreData.validationData, (KSPriceBasedDCAIntentValidator.DCAValidationData)
      );
      validationData.amountOutLimits[0] = 1e9 << 128 | actualAmountOut - 1; //invalid amountOut
      validationData.amountOutLimits[1] = 1e9 << 128 | actualAmountOut - 1; //invalid amountOut
      validationData.amountOutLimits[2] = 1e9 << 128 | actualAmountOut - 1; //invalid amountOut
      intentData.coreData.validationData = abi.encode(validationData);

      _setUpMainAddress(intentData, false);

      IKSSessionIntentRouter.ActionData memory actionData =
        _getActionData(intentData.tokenData, _adjustDeadline(swapCalldata));

      vm.warp(executionTime);
      (address caller, bytes memory daSignature, bytes memory gdSignature) =
        _getCallerAndSignatures(mode, actionData);

      bytes32 intentHash = router.hashTypedIntentData(intentData);

      vm.startPrank(caller);
      vm.expectRevert(
        abi.encodeWithSelector(
          KSPriceBasedDCAIntentValidator.InvalidAmountOut.selector,
          1e9,
          actualAmountOut - 1,
          actualAmountOut
        )
      );
      router.execute(intentHash, daSignature, guardian, gdSignature, actionData);
      vm.stopPrank();
    }
  }

  function test_swapAlreadyExecuted(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    uint256 swapNo = bound(seed, 0, timestamps.length);

    for (uint256 i; i < timestamps.length; i++) {
      uint32 executionTime = timestamps[i];
      deadline = timestamps[i] + 10;
      swap = i;
      minAmountOut = 9e22;
      swapCalldata = _adjustMinReturnAmount(swapCalldata);

      IKSSessionIntentRouter.IntentData memory intentData = _getIntentData();

      _setUpMainAddress(intentData, false);

      IKSSessionIntentRouter.ActionData memory actionData =
        _getActionData(intentData.tokenData, _adjustDeadline(swapCalldata));

      vm.warp(executionTime);
      (address caller, bytes memory daSignature, bytes memory gdSignature) =
        _getCallerAndSignatures(mode, actionData);

      bytes32 intentHash = router.hashTypedIntentData(intentData);

      vm.startPrank(caller);
      router.execute(intentHash, daSignature, guardian, gdSignature, actionData);

      //try to execute again
      if (i == swapNo) {
        actionData.nonce = nonce++;
        (, daSignature, gdSignature) = _getCallerAndSignatures(mode, actionData);
        vm.expectRevert(
          abi.encodeWithSelector(KSPriceBasedDCAIntentValidator.SwapAlreadyExecuted.selector)
        );
        router.execute(intentHash, daSignature, guardian, gdSignature, actionData);
      }
      vm.stopPrank();
    }
  }

  function _getIntentData()
    internal
    view
    returns (IKSSessionIntentRouter.IntentData memory intentData)
  {
    KSPriceBasedDCAIntentValidator.DCAValidationData memory validationData;
    validationData.srcToken = tokenIn;
    validationData.dstToken = tokenOut;
    validationData.amountIns = amountIns;
    validationData.amountOutLimits = amountOutLimits;
    validationData.recipient = recipient;

    IKSSessionIntentRouter.IntentCoreData memory coreData = IKSSessionIntentRouter.IntentCoreData({
      mainAddress: mainAddress,
      delegatedAddress: delegatedAddress,
      startTime: block.timestamp + 10,
      endTime: deadline,
      actionContracts: _toArray(swapRouter),
      actionSelectors: _toArray(IKSSwapRouter.swap.selector),
      validator: address(dcaValidator),
      validationData: abi.encode(validationData)
    });

    IKSSessionIntentRouter.TokenData memory tokenData;
    tokenData.erc20Data = new IKSSessionIntentRouter.ERC20Data[](1);
    tokenData.erc20Data[0] = IKSSessionIntentRouter.ERC20Data({token: tokenIn, amount: amountIn});

    intentData = IKSSessionIntentRouter.IntentData({coreData: coreData, tokenData: tokenData});
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
  ) internal returns (IKSSessionIntentRouter.ActionData memory actionData) {
    actionData = IKSSessionIntentRouter.ActionData({
      tokenData: tokenData,
      actionSelectorId: 0,
      actionCalldata: actionCalldata,
      validatorData: abi.encode(swap),
      extraData: '',
      deadline: deadline,
      nonce: nonce++
    });
  }

  function _adjustAmountIn(bytes memory callData, uint256 amountIn)
    internal
    pure
    returns (bytes memory)
  {
    IKSSwapRouter.SwapExecutionParams memory params =
      abi.decode(callData, (IKSSwapRouter.SwapExecutionParams));

    params.desc.amount = amountIn;

    return abi.encode(params);
  }

  function _adjustMinReturnAmount(bytes memory callData) internal view returns (bytes memory) {
    IKSSwapRouter.SwapExecutionParams memory params =
      abi.decode(callData, (IKSSwapRouter.SwapExecutionParams));

    params.desc.minReturnAmount = minAmountOut;

    return abi.encode(params);
  }

  function _adjustDeadline(bytes memory callData) internal view returns (bytes memory) {
    IKSSwapRouter.SwapExecutionParams memory params =
      abi.decode(callData, (IKSSwapRouter.SwapExecutionParams));

    SwapExecutorDescription memory desc = abi.decode(params.targetData, (SwapExecutorDescription));

    desc.deadline = deadline;
    params.targetData = abi.encode(desc);

    return abi.encode(params);
  }
}
