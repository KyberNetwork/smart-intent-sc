// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.t.sol';

import 'ks-common-sc/libraries/token/TokenHelper.sol';
import 'src/validators/KSLiquidityRemoveUniV4IntentValidator.sol';
import 'test/common/Permit.sol';

contract RemoveLiquidityUniV4Test is BaseTest {
  using SafeERC20 for IERC20;
  using TokenHelper for address;
  using StateLibrary for IPoolManager;
  using ConditionLibrary for IKSConditionBasedValidator.Condition;

  address pm = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
  address uniV4TokenOwner = 0x1f2F10D1C40777AE1Da742455c65828FF36Df387;
  uint256 uniV4TokenId = 36_850; // out range position
  int24 tickLower;
  int24 tickUpper;
  int24 currentTick;
  uint160 currentPrice;
  uint256 liquidity;
  address token0 = TokenHelper.NATIVE_ADDRESS;
  address token1 = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
  uint256 fee0 = 0.1 ether;
  uint256 fee1 = 400e6;
  uint256 amount0 = 0.5 ether;
  uint256 amount1 = 100e6;
  address nftOwner;
  uint256 constant MAGIC_NUMBER_NOT_TRANSFER = uint256(keccak256('NOT_TRANSFER'));
  uint256 constant MAGIC_NUMBER_TRANSFER_99PERCENT = uint256(keccak256('99PERCENT'));
  uint256 constant MAGIC_NUMBER_TRANSFER_98PERCENT = uint256(keccak256('98PERCENT'));
  uint256 magicNumber;
  uint256 minPercentsBps = 9900;

  KSLiquidityRemoveUniV4IntentValidator rmLqValidator;

  struct FuzzStruct {
    uint256 liquidityToRemove;
    bool usePermit;
    bool withSignedIntent;
    ConditionType conditionType;
    bool conditionPass;
    bool positionOutRange;
    bool outLeft;
    uint256 minPercentsBps;
  }

  function setUp() public override {
    FORK_BLOCK = 22_937_800;
    super.setUp();

    rmLqValidator = new KSLiquidityRemoveUniV4IntentValidator();
    address[] memory validators = new address[](1);
    validators[0] = address(rmLqValidator);
    nftOwner = mainAddress;
    vm.prank(owner);
    router.whitelistValidators(validators, true);

    (, uint256 positionIn) = IPositionManager(pm).getPoolAndPositionInfo(uniV4TokenId);
    IPoolManager poolManager = IPositionManager(pm).poolManager();
    address posOwner = IERC721(pm).ownerOf(uniV4TokenId);
    vm.prank(posOwner);
    IERC721(pm).safeTransferFrom(posOwner, mainAddress, uniV4TokenId);

    (PoolKey memory poolKey,) = IPositionManager(pm).getPoolAndPositionInfo(uniV4TokenId);
    bytes32 poolId = _getPoolId(poolKey);
    (currentPrice, currentTick,,) = poolManager.getSlot0(poolId);
    (tickLower, tickUpper) = _getTickRange(positionIn);
    liquidity = IPositionManager(pm).getPositionLiquidity(uniV4TokenId);
    assertTrue(currentTick > tickUpper, 'currentTick > tickLower');
  }

  function testFuzz_RemoveLiquidity(FuzzStruct memory fuzzStruct) public {
    if (!fuzzStruct.positionOutRange) {
      _overrideParams();
    }
    _boundStruct(fuzzStruct);

    (uint256 received0, uint256 received1, uint256 unclaimedFee0, uint256 unclaimedFee1) =
    IPositionManager(pm).poolManager().computePositionValues(
      IPositionManager(pm), uniV4TokenId, fuzzStruct.liquidityToRemove
    );

    fee0 = unclaimedFee0;
    fee1 = unclaimedFee1;

    if (fuzzStruct.liquidityToRemove == 0) {
      assertEq(received0, 0, 'received0 should be 0');
      assertEq(received1, 0, 'received1 should be 0');
    } else if (fuzzStruct.positionOutRange) {
      assertEq(received0, 0, 'received0 should be 0');
    }

    assertGt(unclaimedFee0, 0, 'unclaimedFee0 should be greater than 0');
    assertGt(unclaimedFee1, 0, 'unclaimedFee1 should be greater than 0');

    received0 += unclaimedFee0;
    received1 += unclaimedFee1;

    IKSConditionBasedValidator.Condition[][] memory conditions =
      new IKSConditionBasedValidator.Condition[][](1);

    conditions[0] = new IKSConditionBasedValidator.Condition[](1);
    conditions[0][0] = RemoveLiquidityUniV4Test(address(this)).getCondition(
      IKSConditionBasedValidator.Condition({conditionType: fuzzStruct.conditionType, data: ''}),
      fuzzStruct.conditionPass
    );

    IKSSessionIntentRouter.IntentData memory intentData =
      _getIntentData(fuzzStruct.usePermit, abi.encode(conditions));

    _setUpMainAddress(intentData, fuzzStruct.withSignedIntent, uniV4TokenId, !fuzzStruct.usePermit);

    IKSSessionIntentRouter.ActionData memory actionData =
      _getActionData(intentData.tokenData, fuzzStruct.liquidityToRemove);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    bytes memory maSignature = _getMASignature(intentData);

    uint256 balance0Before = token0.balanceOf(mainAddress);
    uint256 balance1Before = token1.balanceOf(mainAddress);

    bool isRevert;
    vm.startPrank(caller);
    if (fuzzStruct.withSignedIntent) {
      if (!fuzzStruct.conditionPass || minPercentsBps > ConditionLibrary.BPS) {
        isRevert = true;
        if (!fuzzStruct.conditionPass) {
          vm.expectRevert(IKSConditionBasedValidator.ConditionsNotMet.selector);
        } else if (minPercentsBps > ConditionLibrary.BPS) {
          vm.expectRevert(KSLiquidityRemoveUniV4IntentValidator.InvalidOutputAmount.selector);
        }
      }
      router.executeWithSignedIntent(
        intentData, maSignature, daSignature, guardian, gdSignature, actionData
      );
    } else {
      bytes32 hash = router.hashTypedIntentData(intentData);
      if (!fuzzStruct.conditionPass || minPercentsBps > ConditionLibrary.BPS) {
        isRevert = true;
        if (!fuzzStruct.conditionPass) {
          vm.expectRevert(IKSConditionBasedValidator.ConditionsNotMet.selector);
        } else if (minPercentsBps > ConditionLibrary.BPS) {
          vm.expectRevert(KSLiquidityRemoveUniV4IntentValidator.InvalidOutputAmount.selector);
        }
      }
      router.execute(hash, daSignature, guardian, gdSignature, actionData);
    }

    if (!isRevert) {
      uint256 balance0After = token0.balanceOf(mainAddress);
      uint256 balance1After = token1.balanceOf(mainAddress);
      assertEq(balance0After - balance0Before, received0, 'invalid token0 received');
      assertEq(balance1After - balance1Before, received1, 'invalid token1 received');
    }
  }

  function test_RemoveSuccess_DefaultConditions(bool withPermit) public {
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(withPermit, '');

    _setUpMainAddress(intentData, false, uniV4TokenId, !withPermit);

    IKSSessionIntentRouter.ActionData memory actionData =
      _getActionData(intentData.tokenData, liquidity);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    vm.warp(block.timestamp + 100);

    vm.startPrank(caller);
    router.execute(
      router.hashTypedIntentData(intentData), daSignature, guardian, gdSignature, actionData
    );
  }

  function testRevert_NotMeetConditions_YieldBased(bool withPermit) public {
    // pass price based condition, but fail yield based condition
    IKSConditionBasedValidator.Condition[][] memory conditions =
      new IKSConditionBasedValidator.Condition[][](1);
    conditions[0] = new IKSConditionBasedValidator.Condition[](2);
    conditions[0][0] = IKSConditionBasedValidator.Condition({
      conditionType: ConditionLibrary.PRICE_BASED,
      data: abi.encode(PriceCondition({minPrice: 0, maxPrice: type(uint160).max}))
    });

    conditions[0][1] = IKSConditionBasedValidator.Condition({
      conditionType: ConditionLibrary.YIELD_BASED,
      data: abi.encode(
        YieldCondition({
          targetYieldBps: 1e18,
          initialAmounts: (uint256(10_000 ether) << 128) | uint256(10_000e6)
        })
      )
    });

    IKSSessionIntentRouter.IntentData memory intentData =
      _getIntentData(withPermit, abi.encode(conditions));

    _setUpMainAddress(intentData, false, uniV4TokenId, !withPermit);

    IKSSessionIntentRouter.ActionData memory actionData =
      _getActionData(intentData.tokenData, liquidity);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    vm.warp(block.timestamp + 100);
    bytes32 intentDataHash = router.hashTypedIntentData(intentData);
    vm.startPrank(caller);
    vm.expectRevert(IKSConditionBasedValidator.ConditionsNotMet.selector);
    router.execute(intentDataHash, daSignature, guardian, gdSignature, actionData);
  }

  function testRevert_NotMeetConditions_TimeBased(bool withPermit) public {
    // pass price based condition, but fail time based condition
    IKSConditionBasedValidator.Condition[][] memory conditions =
      new IKSConditionBasedValidator.Condition[][](1);
    conditions[0] = new IKSConditionBasedValidator.Condition[](2);
    conditions[0][0] = IKSConditionBasedValidator.Condition({
      conditionType: ConditionLibrary.PRICE_BASED,
      data: abi.encode(PriceCondition({minPrice: 0, maxPrice: type(uint160).max}))
    });

    conditions[0][1] = IKSConditionBasedValidator.Condition({
      conditionType: ConditionLibrary.TIME_BASED,
      data: abi.encode(
        TimeCondition({startTimestamp: block.timestamp + 100, endTimestamp: block.timestamp + 200})
      )
    });

    IKSSessionIntentRouter.IntentData memory intentData =
      _getIntentData(withPermit, abi.encode(conditions));

    _setUpMainAddress(intentData, false, uniV4TokenId, !withPermit);

    IKSSessionIntentRouter.ActionData memory actionData =
      _getActionData(intentData.tokenData, liquidity);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    bytes32 intentDataHash = router.hashTypedIntentData(intentData);
    vm.startPrank(caller);
    vm.expectRevert(IKSConditionBasedValidator.ConditionsNotMet.selector);
    router.execute(intentDataHash, daSignature, guardian, gdSignature, actionData);
  }

  function testRevert_NotMeetConditions_PriceBased(bool withPermit) public {
    IKSConditionBasedValidator.Condition[][] memory conditions =
      new IKSConditionBasedValidator.Condition[][](1);
    conditions[0] = new IKSConditionBasedValidator.Condition[](2);
    conditions[0][0] = IKSConditionBasedValidator.Condition({
      conditionType: ConditionLibrary.PRICE_BASED,
      data: abi.encode(PriceCondition({minPrice: currentPrice + 100, maxPrice: currentPrice + 1000}))
    });

    conditions[0][1] = IKSConditionBasedValidator.Condition({
      conditionType: ConditionLibrary.YIELD_BASED,
      data: abi.encode(
        YieldCondition({
          targetYieldBps: 0,
          initialAmounts: (uint256(1 ether) << 128) | uint256(1000e6)
        })
      )
    });

    IKSSessionIntentRouter.IntentData memory intentData =
      _getIntentData(withPermit, abi.encode(conditions));

    _setUpMainAddress(intentData, false, uniV4TokenId, !withPermit);

    IKSSessionIntentRouter.ActionData memory actionData =
      _getActionData(intentData.tokenData, liquidity);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    bytes32 intentDataHash = router.hashTypedIntentData(intentData);
    vm.startPrank(caller);
    vm.expectRevert(IKSConditionBasedValidator.ConditionsNotMet.selector);
    router.execute(intentDataHash, daSignature, guardian, gdSignature, actionData);
  }

  function test_RemoveSuccess_PriceBased(bool withPermit) public {
    IKSConditionBasedValidator.Condition[][] memory conditions =
      new IKSConditionBasedValidator.Condition[][](2);
    conditions[0] = new IKSConditionBasedValidator.Condition[](1);
    conditions[0][0] = IKSConditionBasedValidator.Condition({
      conditionType: ConditionLibrary.YIELD_BASED,
      data: abi.encode(
        YieldCondition({
          targetYieldBps: 0,
          initialAmounts: (uint256(1 ether) << 128) | uint256(1000e6) //3435
        })
      )
    });

    conditions[1] = new IKSConditionBasedValidator.Condition[](1);
    conditions[1][0] = IKSConditionBasedValidator.Condition({
      conditionType: ConditionLibrary.PRICE_BASED,
      data: abi.encode(PriceCondition({minPrice: currentPrice + 100, maxPrice: currentPrice + 1000}))
    });

    IKSSessionIntentRouter.IntentData memory intentData =
      _getIntentData(withPermit, abi.encode(conditions));

    _setUpMainAddress(intentData, false, uniV4TokenId, !withPermit);

    IKSSessionIntentRouter.ActionData memory actionData =
      _getActionData(intentData.tokenData, liquidity);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    bytes32 intentDataHash = router.hashTypedIntentData(intentData);
    vm.startPrank(caller);
    router.execute(intentDataHash, daSignature, guardian, gdSignature, actionData);
  }

  function test_RemoveSuccess_TimeBased(bool withPermit) public {
    IKSConditionBasedValidator.Condition[][] memory conditions =
      new IKSConditionBasedValidator.Condition[][](2);
    conditions[0] = new IKSConditionBasedValidator.Condition[](1);
    conditions[0][0] = IKSConditionBasedValidator.Condition({
      conditionType: ConditionLibrary.YIELD_BASED,
      data: abi.encode(
        YieldCondition({
          targetYieldBps: 0,
          initialAmounts: (uint256(1 ether) << 128) | uint256(1000e6) //3435
        })
      )
    });

    conditions[1] = new IKSConditionBasedValidator.Condition[](1);
    conditions[1][0] = IKSConditionBasedValidator.Condition({
      conditionType: ConditionLibrary.TIME_BASED,
      data: abi.encode(
        TimeCondition({startTimestamp: block.timestamp - 100, endTimestamp: block.timestamp + 200})
      )
    });

    IKSSessionIntentRouter.IntentData memory intentData =
      _getIntentData(withPermit, abi.encode(conditions));

    _setUpMainAddress(intentData, false, uniV4TokenId, !withPermit);

    IKSSessionIntentRouter.ActionData memory actionData =
      _getActionData(intentData.tokenData, liquidity);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    bytes32 intentDataHash = router.hashTypedIntentData(intentData);
    vm.startPrank(caller);
    router.execute(intentDataHash, daSignature, guardian, gdSignature, actionData);
  }

  function test_RemoveSuccess_FailFirstConjunction_PassSecondOne() public {
    IKSConditionBasedValidator.Condition[][] memory conditions =
      new IKSConditionBasedValidator.Condition[][](2);
    conditions[0] = new IKSConditionBasedValidator.Condition[](1);
    conditions[0][0] = IKSConditionBasedValidator.Condition({
      conditionType: ConditionLibrary.PRICE_BASED,
      data: abi.encode(PriceCondition({minPrice: currentPrice + 100, maxPrice: currentPrice + 1000}))
    });
    conditions[1] = new IKSConditionBasedValidator.Condition[](1);
    conditions[1][0] = IKSConditionBasedValidator.Condition({
      conditionType: ConditionLibrary.YIELD_BASED,
      data: abi.encode(
        YieldCondition({
          targetYieldBps: 1000, //10%
          initialAmounts: (uint256(1 ether) << 128) | uint256(1000e6) //3435
        })
      )
    });

    IKSSessionIntentRouter.IntentData memory intentData =
      _getIntentData(false, abi.encode(conditions));

    _setUpMainAddress(intentData, false, uniV4TokenId, true);

    IKSSessionIntentRouter.ActionData memory actionData =
      _getActionData(intentData.tokenData, liquidity);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    bytes32 intentDataHash = router.hashTypedIntentData(intentData);
    vm.startPrank(caller);
    router.execute(intentDataHash, daSignature, guardian, gdSignature, actionData);
  }

  function test_executeSignedIntent_RemoveSuccess() public {
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(true, '');
    _setUpMainAddress(intentData, true, uniV4TokenId, false);
    IKSSessionIntentRouter.ActionData memory actionData =
      _getActionData(intentData.tokenData, liquidity);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    bytes memory maSignature = _getMASignature(intentData);

    vm.startPrank(caller);
    router.executeWithSignedIntent(
      intentData, maSignature, daSignature, guardian, gdSignature, actionData
    );
  }

  function testRevert_validationAfterExecution_fail(uint256 liq) public {
    liq = bound(liq, 0, liquidity);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(true, '');
    _setUpMainAddress(intentData, false, uniV4TokenId, false);

    magicNumber = MAGIC_NUMBER_NOT_TRANSFER;

    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(intentData.tokenData, liq);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    bytes32 intentDataHash = router.hashTypedIntentData(intentData);
    vm.startPrank(caller);
    vm.expectRevert(KSLiquidityRemoveUniV4IntentValidator.InvalidOutputAmount.selector);
    router.execute(intentDataHash, daSignature, guardian, gdSignature, actionData);
  }

  function testRevert_validationAfterExecution_InvalidOwner(uint256 liq) public {
    liq = bound(liq, 0, liquidity);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(true, '');
    _setUpMainAddress(intentData, false, uniV4TokenId, false);

    nftOwner = address(0);

    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(intentData.tokenData, liq);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    bytes32 intentDataHash = router.hashTypedIntentData(intentData);
    vm.startPrank(caller);
    vm.expectRevert(KSLiquidityRemoveUniV4IntentValidator.InvalidOwner.selector);
    router.execute(intentDataHash, daSignature, guardian, gdSignature, actionData);
  }

  function test_RemoveSuccess_Transfer99Percent(uint256 liq) public {
    liq = bound(liq, 0, liquidity);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(true, '');
    _setUpMainAddress(intentData, false, uniV4TokenId, false);

    magicNumber = MAGIC_NUMBER_TRANSFER_99PERCENT;

    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(intentData.tokenData, liq);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    bytes32 intentDataHash = router.hashTypedIntentData(intentData);
    vm.startPrank(caller);
    router.execute(intentDataHash, daSignature, guardian, gdSignature, actionData);
  }

  function testRevert_Transfer98Percent(uint256 liq) public {
    liq = bound(liq, 0, liquidity);
    KSSessionIntentRouter.IntentData memory intentData = _getIntentData(true, '');
    _setUpMainAddress(intentData, false, uniV4TokenId, false);

    magicNumber = MAGIC_NUMBER_TRANSFER_98PERCENT;

    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(intentData.tokenData, liq);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    bytes32 intentDataHash = router.hashTypedIntentData(intentData);
    vm.startPrank(caller);
    vm.expectRevert(KSLiquidityRemoveUniV4IntentValidator.InvalidOutputAmount.selector);
    router.execute(intentDataHash, daSignature, guardian, gdSignature, actionData);
  }

  function _getIntentData(bool withPermit, bytes memory conditions)
    internal
    returns (IKSSessionIntentRouter.IntentData memory intentData)
  {
    KSLiquidityRemoveUniV4IntentValidator.RemoveLiquidityValidationData memory validationData;
    validationData.nftAddresses = new address[](1);
    validationData.nftAddresses[0] = pm;
    validationData.nftIds = new uint256[](1);
    validationData.nftIds[0] = uniV4TokenId;
    validationData.outputTokens = new address[][](1);
    validationData.outputTokens[0] = new address[](2);
    validationData.outputTokens[0][0] = token0;
    validationData.outputTokens[0][1] = token1;
    validationData.minPercentsBps = new uint256[](1);
    validationData.minPercentsBps[0] = minPercentsBps;

    validationData.recipient = mainAddress;

    if (conditions.length == 0) {
      IKSConditionBasedValidator.Condition[][] memory conditions =
        new IKSConditionBasedValidator.Condition[][](1);

      conditions[0] = new IKSConditionBasedValidator.Condition[](2);
      conditions[0][0] = IKSConditionBasedValidator.Condition({
        conditionType: ConditionLibrary.YIELD_BASED,
        data: abi.encode(
          YieldCondition({
            targetYieldBps: 0,
            initialAmounts: (uint256(amount0) << 128) | uint256(amount1)
          })
        )
      });

      conditions[0][1] = IKSConditionBasedValidator.Condition({
        conditionType: ConditionLibrary.PRICE_BASED,
        data: abi.encode(PriceCondition({minPrice: 0, maxPrice: type(uint160).max}))
      });
      validationData.dnfExpressions = new IKSConditionBasedValidator.DNFExpression[](1);
      validationData.dnfExpressions[0].conditions = conditions;
    } else {
      IKSConditionBasedValidator.Condition[][] memory conditions =
        abi.decode(conditions, (IKSConditionBasedValidator.Condition[][]));
      validationData.dnfExpressions = new IKSConditionBasedValidator.DNFExpression[](1);
      validationData.dnfExpressions[0].conditions = conditions;
    }

    IKSSessionIntentRouter.IntentCoreData memory coreData = IKSSessionIntentRouter.IntentCoreData({
      mainAddress: mainAddress,
      delegatedAddress: delegatedAddress,
      actionContracts: _toArray(address(mockActionContract)),
      actionSelectors: _toArray(MockActionContract.removeUniswapV4.selector),
      validator: address(rmLqValidator),
      validationData: abi.encode(validationData)
    });

    bytes memory permitData;
    if (withPermit) {
      permitData = _getPermitData(uniV4TokenId);
    }

    IKSSessionIntentRouter.TokenData memory tokenData;
    tokenData.erc721Data = new IKSSessionIntentRouter.ERC721Data[](1);
    tokenData.erc721Data[0] =
      IKSSessionIntentRouter.ERC721Data({token: pm, tokenId: uniV4TokenId, permitData: permitData});

    intentData =
      IKSSessionIntentRouter.IntentData({coreData: coreData, tokenData: tokenData, extraData: ''});
  }

  function _getActionData(IKSSessionIntentRouter.TokenData memory tokenData, uint256 liquidity)
    internal
    view
    returns (IKSSessionIntentRouter.ActionData memory actionData)
  {
    actionData = IKSSessionIntentRouter.ActionData({
      tokenData: tokenData,
      actionSelectorId: 0,
      actionCalldata: abi.encode(pm, uniV4TokenId, nftOwner, token0, token1, liquidity, magicNumber),
      validatorData: abi.encode(0, fee0, fee1, liquidity),
      extraData: '',
      deadline: block.timestamp + 1 days,
      nonce: 0
    });
  }

  function _setUpMainAddress(
    IKSSessionIntentRouter.IntentData memory intentData,
    bool withSignedIntent,
    uint256 tokenId,
    bool needApproval
  ) internal {
    vm.startPrank(mainAddress);
    if (!withSignedIntent) {
      router.delegate(intentData);
    }
    if (needApproval) {
      IERC721(pm).approve(address(router), tokenId);
    }
    vm.stopPrank();
  }

  function _getTickRange(uint256 posInfo)
    internal
    pure
    returns (int24 _tickLower, int24 _tickUpper)
  {
    assembly {
      _tickLower := signextend(2, shr(8, posInfo))
      _tickUpper := signextend(2, shr(32, posInfo))
    }
  }

  function _getPoolId(PoolKey memory poolKey) internal pure returns (bytes32 poolId) {
    assembly {
      poolId := keccak256(poolKey, 0xa0)
    }
  }

  function _getPermitData(uint256 tokenId) internal view returns (bytes memory permitData) {
    bytes32 digest =
      Permit.uniswapV4Permit(pm, address(router), tokenId, 0, block.timestamp + 1 days);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(mainAddressKey, digest);
    bytes memory signature = abi.encodePacked(r, s, v);

    permitData = abi.encode(block.timestamp + 1 days, 0, signature);
  }

  function _boundStruct(FuzzStruct memory fuzzStruct) internal {
    fuzzStruct.liquidityToRemove = bound(fuzzStruct.liquidityToRemove, 0, liquidity);
    minPercentsBps = bound(fuzzStruct.minPercentsBps, 0, ConditionLibrary.BPS * 100);

    (uint256 received0, uint256 received1, uint256 unclaimedFee0, uint256 unclaimedFee1) =
    IPositionManager(pm).poolManager().computePositionValues(
      IPositionManager(pm), uniV4TokenId, liquidity
    );

    amount0 = received0;
    amount1 = received1;

    uint256 typeUint = bound(uint256(ConditionType.unwrap(fuzzStruct.conditionType)), 0, 2);
    if (typeUint == 0) {
      fuzzStruct.conditionType = ConditionLibrary.YIELD_BASED;
    } else if (typeUint == 1) {
      fuzzStruct.conditionType = ConditionLibrary.PRICE_BASED;
    } else {
      fuzzStruct.conditionType = ConditionLibrary.TIME_BASED;
    }
  }

  function getCondition(
    IKSConditionBasedValidator.Condition calldata conditionType,
    bool conditionPass
  ) external view returns (IKSConditionBasedValidator.Condition memory) {
    if (conditionType.isType(ConditionLibrary.YIELD_BASED)) {
      if (conditionPass) {
        return IKSConditionBasedValidator.Condition({
          conditionType: ConditionLibrary.YIELD_BASED,
          data: abi.encode(
            YieldCondition({
              targetYieldBps: 10, // 0.1%
              initialAmounts: (uint256(amount0) << 128) | uint256(amount1)
            })
          )
        });
      }

      return IKSConditionBasedValidator.Condition({
        conditionType: ConditionLibrary.YIELD_BASED,
        data: abi.encode(
          YieldCondition({
            targetYieldBps: 100_000, // 1000%
            initialAmounts: (uint256(amount0) << 128) | uint256(amount1)
          })
        )
      });
    } else if (conditionType.isType(ConditionLibrary.PRICE_BASED)) {
      if (conditionPass) {
        return IKSConditionBasedValidator.Condition({
          conditionType: ConditionLibrary.PRICE_BASED,
          data: abi.encode(
            PriceCondition({minPrice: currentPrice - 100, maxPrice: currentPrice + 100})
          )
        });
      }

      return IKSConditionBasedValidator.Condition({
        conditionType: ConditionLibrary.PRICE_BASED,
        data: abi.encode(
          PriceCondition({minPrice: currentPrice + 100, maxPrice: currentPrice + 1000})
        )
      });
    } else if (conditionType.isType(ConditionLibrary.TIME_BASED)) {
      if (conditionPass) {
        return IKSConditionBasedValidator.Condition({
          conditionType: ConditionLibrary.TIME_BASED,
          data: abi.encode(
            TimeCondition({startTimestamp: block.timestamp - 100, endTimestamp: block.timestamp + 100})
          )
        });
      }
      return IKSConditionBasedValidator.Condition({
        conditionType: ConditionLibrary.TIME_BASED,
        data: abi.encode(
          TimeCondition({startTimestamp: block.timestamp + 100, endTimestamp: block.timestamp + 1000})
        )
      });
    }
  }

  function _overrideParams() internal {
    uniV4TokenId = 36_343; // in range position
    IPoolManager poolManager = IPositionManager(pm).poolManager();
    address posOwner = IERC721(pm).ownerOf(uniV4TokenId);
    vm.prank(posOwner);
    IERC721(pm).safeTransferFrom(posOwner, mainAddress, uniV4TokenId);

    (PoolKey memory poolKey, uint256 posInfo) =
      IPositionManager(pm).getPoolAndPositionInfo(uniV4TokenId);
    bytes32 poolId = _getPoolId(poolKey);
    (currentPrice, currentTick,,) = poolManager.getSlot0(poolId);
    (tickLower, tickUpper) = _getTickRange(posInfo);
    liquidity = IPositionManager(pm).getPositionLiquidity(uniV4TokenId);
    assertTrue(currentTick > tickLower, 'currentTick > tickLower');
    assertTrue(currentTick < tickUpper, 'currentTick < tickUpper');
  }
}
