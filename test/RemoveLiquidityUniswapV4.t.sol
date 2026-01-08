// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.t.sol';

import 'ks-common-sc/src/libraries/token/TokenHelper.sol';
import 'src/hooks/base/BaseConditionalHook.sol';
import 'src/hooks/remove-liq/KSRemoveLiquidityUniswapV4Hook.sol';
import 'src/types/ConditionTree.sol';

import {IERC721} from 'openzeppelin-contracts/contracts/interfaces/IERC721.sol';
import {IUniswapV3PM} from 'src/interfaces/uniswapv3/IUniswapV3PM.sol';
import {IPositionManager} from 'src/interfaces/uniswapv4/IPositionManager.sol';
import {Actions} from 'src/interfaces/uniswapv4/Types.sol';
import 'test/common/Permit.sol';

contract RemoveLiquidityUniswapV4Test is BaseTest {
  using SafeERC20 for IERC20;
  using TokenHelper for address;
  using StateLibrary for IPoolManager;
  using ArraysHelper for *;

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
  uint256 intentFeesPercent0 = 10_000; // 1%
  uint256 intentFeesPercent1 = 10_000; // 1%
  uint256 constant NOT_TRANSFER = uint256(keccak256('NOT_TRANSFER'));
  ConditionType constant TIME_BASED = ConditionType.wrap(keccak256('TIME_BASED'));
  ConditionType constant PRICE_BASED = ConditionType.wrap(keccak256('PRICE_BASED'));
  ConditionType constant YIELD_BASED = ConditionType.wrap(keccak256('YIELD_BASED'));
  OperationType constant AND = OperationType.AND;
  OperationType constant OR = OperationType.OR;
  uint256 magicNumber = 1e6;
  uint256 maxFeePercents = 20_000; // 2%
  Node[] internal _nodes;
  mapping(uint256 => bool) internal _isLeaf;
  uint256 constant PRECISION = 1_000_000;
  address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  bool wrapOrUnwrap;
  bool takeUnclaimedFees;

  KSRemoveLiquidityUniswapV4Hook rmLqHook;

  struct FuzzStruct {
    uint256 seed;
    uint256 liquidityToRemove;
    bool usePermit;
    bool withSignedIntent;
    ConditionType conditionType;
    bool conditionPass;
    bool positionOutRange;
    bool outLeft;
    uint256 maxFeePercents;
  }

  function setUp() public override {
    FORK_BLOCK = 22_937_800;
    super.setUp();

    rmLqHook = new KSRemoveLiquidityUniswapV4Hook(weth);
    nftOwner = mainAddress;

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

    vm.prank(admin);
    router.grantRole(ACTION_CONTRACT_ROLE, address(pm));
  }

  function testFuzz_RemoveLiquidityUniV4(FuzzStruct memory fuzzStruct) public {
    if (!fuzzStruct.positionOutRange) {
      _overrideParams();
    }
    _boundStruct(fuzzStruct);
    wrapOrUnwrap = bound(fuzzStruct.seed, 0, 1) == 1;

    (uint256 liqAmount0, uint256 liqAmount1, uint256 unclaimedFee0, uint256 unclaimedFee1) = IPositionManager(
        pm
      ).poolManager()
      .computePositionValues(IPositionManager(pm), uniV4TokenId, fuzzStruct.liquidityToRemove);

    fee0 = unclaimedFee0;
    fee1 = unclaimedFee1;

    if (fuzzStruct.liquidityToRemove == 0) {
      assertEq(liqAmount0, 0, 'liqAmount0 should be 0');
      assertEq(liqAmount1, 0, 'liqAmount1 should be 0');
    } else if (fuzzStruct.positionOutRange) {
      assertEq(liqAmount0, 0, 'liqAmount0 should be 0');
    }

    assertGt(unclaimedFee0, 0, 'unclaimedFee0 should be greater than 0');
    assertGt(unclaimedFee1, 0, 'unclaimedFee1 should be greater than 0');

    Node[] memory nodes = _randomNodes(fuzzStruct);
    ConditionTree memory conditionTree = this.buildConditionTree(nodes, fee0, fee1, currentPrice);
    bool pass = this.callLibrary(conditionTree, 0);

    IntentData memory intentData = _getIntentData(fuzzStruct.usePermit, nodes);

    _setUpMainAddress(intentData, fuzzStruct.withSignedIntent, uniV4TokenId, !fuzzStruct.usePermit);

    ActionData memory actionData = _getActionData(fuzzStruct.liquidityToRemove);

    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData.coreData, actionData);

    bytes memory maSignature = _getMASignature(intentData);

    if (wrapOrUnwrap) {
      token0 = weth;
    }

    uint256 balance0Before = token0.balanceOf(mainAddress);
    uint256 balance1Before = token1.balanceOf(mainAddress);

    vm.startPrank(caller);
    if (!pass) {
      vm.expectRevert(IKSConditionalHook.ConditionsNotMet.selector);
    }

    if (fuzzStruct.withSignedIntent) {
      router.executeWithSignedIntent(
        intentData, maSignature, dkSignature, guardian, gdSignature, actionData
      );
    } else {
      router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
    }

    if (pass) {
      uint256 balance0After = token0.balanceOf(mainAddress);
      uint256 balance1After = token1.balanceOf(mainAddress);
      uint256 intentFee0 = liqAmount0 * intentFeesPercent0 / 1_000_000;
      uint256 intentFee1 = liqAmount1 * intentFeesPercent1 / 1_000_000;
      assertEq(
        balance0After - balance0Before,
        liqAmount0 - intentFee0 + unclaimedFee0,
        'invalid token0 received'
      );
      assertEq(
        balance1After - balance1Before,
        liqAmount1 - intentFee1 + unclaimedFee1,
        'invalid token1 received'
      );
    }
  }

  function testFuzz_ValidateOutputUniswapV4(FuzzStruct memory fuzz) public {
    wrapOrUnwrap = bound(fuzz.seed, 0, 1) == 1;
    fuzz.liquidityToRemove = bound(fuzz.seed, 0, liquidity);
    takeUnclaimedFees = bound(fuzz.seed, 0, 1) == 1;
    intentFeesPercent0 = bound(fuzz.seed, 0, 1_000_000);
    intentFeesPercent1 = bound(fuzz.seed, 0, 1_000_000);

    (uint256 liqAmount0, uint256 liqAmount1, uint256 unclaimedFee0, uint256 unclaimedFee1) = IPositionManager(
        pm
      ).poolManager()
      .computePositionValues(IPositionManager(pm), uniV4TokenId, fuzz.liquidityToRemove);

    fee0 = unclaimedFee0;
    fee1 = unclaimedFee1;

    IntentData memory intentData = _getIntentData(fuzz.usePermit, new Node[](0));

    _setUpMainAddress(intentData, false, uniV4TokenId, !fuzz.usePermit);

    ActionData memory actionData = _getActionData(fuzz.liquidityToRemove);

    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData.coreData, actionData);

    // always success when dont charge fees on the user's unclaimed fees
    if (fuzz.liquidityToRemove == 0 && !takeUnclaimedFees) {
      router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
      return;
    }

    uint256 minReceived0 = (liqAmount0 * (1_000_000 - maxFeePercents)) / 1_000_000 + unclaimedFee0;
    uint256 minReceived1 = (liqAmount1 * (1_000_000 - maxFeePercents)) / 1_000_000 + unclaimedFee1;

    uint256 actualReceived0 = liqAmount0 + unclaimedFee0;
    uint256 actualReceived1 = liqAmount1 + unclaimedFee1;

    if (takeUnclaimedFees) {
      actualReceived0 -= unclaimedFee0;
      actualReceived1 -= unclaimedFee1;
    }

    if (actualReceived0 < unclaimedFee0 || actualReceived1 < unclaimedFee1) {
      vm.startPrank(caller);
      vm.expectRevert(BaseTickBasedRemoveLiquidityHook.NotEnoughFeesReceived.selector);
      router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
      return;
    }

    uint256 amount0ReceivedForLiquidity = actualReceived0 - unclaimedFee0;
    uint256 amount1ReceivedForLiquidity = actualReceived1 - unclaimedFee1;

    uint256 intentFee0 = (amount0ReceivedForLiquidity * intentFeesPercent0) / 1e6;
    uint256 intentFee1 = (amount1ReceivedForLiquidity * intentFeesPercent1) / 1e6;

    actualReceived0 -= intentFee0;
    actualReceived1 -= intentFee1;

    if (wrapOrUnwrap) {
      token0 = weth;
    }

    uint256 balance0Before = token0.balanceOf(mainAddress);
    uint256 balance1Before = token1.balanceOf(mainAddress);

    vm.startPrank(caller);
    if (actualReceived0 < minReceived0 || actualReceived1 < minReceived1) {
      vm.expectRevert(BaseTickBasedRemoveLiquidityHook.NotEnoughOutputAmount.selector);
      router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
      return;
    }

    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);

    uint256 balance0After = token0.balanceOf(mainAddress);
    uint256 balance1After = token1.balanceOf(mainAddress);

    assertEq(balance0After - balance0Before, actualReceived0, 'invalid token0 received');
    assertEq(balance1After - balance1Before, actualReceived1, 'invalid token1 received');
  }

  function test_RemoveSuccess_DefaultConditions(bool withPermit) public {
    IntentData memory intentData = _getIntentData(withPermit, new Node[](0));

    _setUpMainAddress(intentData, false, uniV4TokenId, !withPermit);

    ActionData memory actionData = _getActionData(liquidity);

    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData.coreData, actionData);

    vm.warp(block.timestamp + 100);

    vm.startPrank(caller);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function test_multiCallToUniV4PositionManager(uint256 seed) public {
    bool unwrap = seed % 2 == 1;
    uint256 liquidityToRemove = bound(seed, 0, liquidity);
    (uint256 liqAmount0, uint256 liqAmount1, uint256 unclaimedFee0, uint256 unclaimedFee1) = IPositionManager(
        pm
      ).poolManager().computePositionValues(IPositionManager(pm), uniV4TokenId, liquidityToRemove);

    bytes[] memory multiCalldata;
    if (!unwrap) {
      bytes memory actions = new bytes(2);
      bytes[] memory params = new bytes[](2);
      actions[0] = bytes1(uint8(Actions.DECREASE_LIQUIDITY));
      params[0] = abi.encode(uniV4TokenId, liquidityToRemove, 0, 0, '');
      actions[1] = bytes1(uint8(Actions.TAKE_PAIR));
      params[1] = abi.encode(address(0), token1, address(router));

      multiCalldata = new bytes[](2);
      multiCalldata[0] = abi.encodeWithSelector(
        IPositionManager.modifyLiquidities.selector, abi.encode(actions, params), type(uint256).max
      );
      multiCalldata[1] = abi.encodeWithSelector(
        IERC721.transferFrom.selector, address(forwarder), mainAddress, uniV4TokenId
      );
    } else {
      bytes memory actions = new bytes(5);
      bytes[] memory params = new bytes[](5);
      actions[0] = bytes1(uint8(Actions.DECREASE_LIQUIDITY));
      params[0] = abi.encode(uniV4TokenId, liquidityToRemove, 0, 0, '');
      actions[1] = bytes1(uint8(Actions.TAKE_PAIR));
      params[1] = abi.encode(address(0), token1, address(pm));
      actions[2] = bytes1(uint8(Actions.WRAP));

      uint256 amount = 0x8000000000000000000000000000000000000000000000000000000000000000; //contract balance
      params[2] = abi.encode(amount);
      actions[3] = bytes1(uint8(Actions.SWEEP));
      params[3] = abi.encode(weth, address(router));
      actions[4] = bytes1(uint8(Actions.SWEEP));
      params[4] = abi.encode(token1, address(router));

      multiCalldata = new bytes[](2);
      multiCalldata[0] = abi.encodeWithSelector(
        IPositionManager.modifyLiquidities.selector, abi.encode(actions, params), type(uint256).max
      );
      multiCalldata[1] = abi.encodeWithSelector(
        IERC721.transferFrom.selector, address(forwarder), mainAddress, uniV4TokenId
      );
    }

    IntentData memory intentData = _getIntentData(false, new Node[](0));
    FeeInfo memory feeInfo;
    {
      feeInfo.protocolRecipient = protocolRecipient;
      feeInfo.partnerFeeConfigs = new FeeConfig[][](2);
      feeInfo.partnerFeeConfigs[0] = _buildPartnersConfigs(
        PartnersFeeConfigBuildParams({
          feeModes: [false].toMemoryArray(),
          partnerFees: [uint24(0.25e6)].toMemoryArray(),
          partnerRecipients: [partnerRecipient].toMemoryArray()
        })
      );

      feeInfo.partnerFeeConfigs[1] = _buildPartnersConfigs(
        PartnersFeeConfigBuildParams({
          feeModes: [false].toMemoryArray(),
          partnerFees: [uint24(0.25e6)].toMemoryArray(),
          partnerRecipients: [makeAddr('partnerRecipient2')].toMemoryArray()
        })
      );
    }

    _setUpMainAddress(intentData, false, uniV4TokenId, true);

    ActionData memory actionData = ActionData({
      erc20Ids: new uint256[](0),
      erc20Amounts: new uint256[](0),
      erc721Ids: [uint256(0)].toMemoryArray(),
      feeInfo: feeInfo,
      actionSelectorId: 1,
      approvalFlags: type(uint256).max,
      actionCalldata: abi.encode(multiCalldata),
      hookActionData: abi.encode(
        0,
        unclaimedFee0,
        unclaimedFee1,
        liquidityToRemove,
        unwrap,
        (intentFeesPercent0 << 128) | intentFeesPercent1
      ),
      extraData: '',
      deadline: block.timestamp + 1 days,
      nonce: 0
    });

    if (unwrap) {
      token0 = weth;
    }

    uint256[2] memory feeBefore =
      [token0.balanceOf(partnerRecipient), token1.balanceOf(makeAddr('partnerRecipient2'))];
    uint256[2] memory protocolFeeBefore =
      [token0.balanceOf(protocolRecipient), token1.balanceOf(protocolRecipient)];
    uint256[2] memory mainAddrBefore =
      [token0.balanceOf(mainAddress), token1.balanceOf(mainAddress)];

    (, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData.coreData, actionData);

    vm.expectEmit(false, false, false, true, address(rmLqHook));
    emit BaseTickBasedRemoveLiquidityHook.LiquidityRemoved(
      address(pm), uniV4TokenId, liquidityToRemove
    );
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);

    uint256 intentFee0 = (liqAmount0 * intentFeesPercent0) / 1e6;
    uint256 intentFee1 = (liqAmount1 * intentFeesPercent1) / 1e6;

    uint256 received0 = liqAmount0 + unclaimedFee0 - intentFee0;
    uint256 received1 = liqAmount1 + unclaimedFee1 - intentFee1;

    uint256[2] memory feeAfter =
      [token0.balanceOf(partnerRecipient), token1.balanceOf(makeAddr('partnerRecipient2'))];
    uint256[2] memory protocolFeeAfter =
      [token0.balanceOf(protocolRecipient), token1.balanceOf(protocolRecipient)];

    assertEq(feeAfter[0] - feeBefore[0], intentFee0 / 4, 'invalid intent fee 0');
    assertEq(feeAfter[1] - feeBefore[1], intentFee1 / 4, 'invalid token1 fee 1');
    assertEq(
      protocolFeeAfter[0] - protocolFeeBefore[0],
      intentFee0 - intentFee0 / 4,
      'invalid protocol fee 0'
    );
    assertEq(
      protocolFeeAfter[1] - protocolFeeBefore[1],
      intentFee1 - intentFee1 / 4,
      'invalid protocol fee 1'
    );

    uint256[2] memory mainAddrAfter = [token0.balanceOf(mainAddress), token1.balanceOf(mainAddress)];

    assertEq(mainAddrAfter[0] - mainAddrBefore[0], received0, 'invalid token0 received');
    assertEq(mainAddrAfter[1] - mainAddrBefore[1], received1, 'invalid token1 received');

    assertEq(token0.balanceOf(address(router)), 0, 'invalid router balance 0');
    assertEq(token1.balanceOf(address(router)), 0, 'invalid router balance 1');
  }

  function testRevert_NotMeetConditions_YieldBased(bool withPermit) public {
    // Tree structure:
    //          AND (index 0)
    //         /            \
    //(true) PRICE_BASED (1)  YIELD_BASED (2) (false)
    Node[] memory nodes = new Node[](3);
    nodes[1] = _createLeafNode(_createPriceCondition(true));
    nodes[2] = _createLeafNode(_createYieldCondition(false));

    uint256[] memory andChildren = new uint256[](2);
    andChildren[0] = 1;
    andChildren[1] = 2;
    nodes[0] = _createNode(andChildren, AND);

    IntentData memory intentData = _getIntentData(withPermit, nodes);

    _setUpMainAddress(intentData, false, uniV4TokenId, !withPermit);

    ActionData memory actionData = _getActionData(liquidity);

    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData.coreData, actionData);

    vm.warp(block.timestamp + 100);
    vm.startPrank(caller);
    vm.expectRevert(IKSConditionalHook.ConditionsNotMet.selector);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function testRevert_NotMeetConditions_TimeBased(bool withPermit) public {
    // Tree structure:
    //          AND (index 0)
    //         /            \
    //(true) PRICE_BASED (1)  TIME_BASED (2) (false)
    Node[] memory nodes = new Node[](3);
    nodes[1] = _createLeafNode(_createPriceCondition(true));
    nodes[2] = _createLeafNode(_createTimeCondition(false));
    uint256[] memory andChildren = new uint256[](2);
    andChildren[0] = 1;
    andChildren[1] = 2;
    nodes[0] = _createNode(andChildren, AND);

    IntentData memory intentData = _getIntentData(withPermit, nodes);

    _setUpMainAddress(intentData, false, uniV4TokenId, !withPermit);

    ActionData memory actionData = _getActionData(liquidity);

    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData.coreData, actionData);

    vm.startPrank(caller);
    vm.expectRevert(IKSConditionalHook.ConditionsNotMet.selector);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function testRevert_NotMeetConditions_PriceBased(bool withPermit) public {
    // Tree structure:
    //          AND (index 0)
    //         /            \
    //(false) PRICE_BASED (1)  YIELD_BASED (2) (true)
    Node[] memory nodes = new Node[](3);
    nodes[1] = _createLeafNode(_createPriceCondition(false));
    nodes[2] = _createLeafNode(_createYieldCondition(true));
    uint256[] memory andChildren = new uint256[](2);
    andChildren[0] = 1;
    andChildren[1] = 2;
    nodes[0] = _createNode(andChildren, AND);

    IntentData memory intentData = _getIntentData(withPermit, nodes);

    _setUpMainAddress(intentData, false, uniV4TokenId, !withPermit);

    ActionData memory actionData = _getActionData(liquidity);

    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData.coreData, actionData);

    vm.startPrank(caller);
    vm.expectRevert(IKSConditionalHook.ConditionsNotMet.selector);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function test_RemoveSuccess_PriceBased(bool withPermit) public {
    // Tree structure:
    //          AND (index 0)
    //         /            \
    //(false) YIELD_BASED (1) PRICE_BASED (2) (true)
    Node[] memory nodes = new Node[](3);
    nodes[1] = _createLeafNode(_createYieldCondition(false));
    nodes[2] = _createLeafNode(_createPriceCondition(true));
    uint256[] memory andChildren = new uint256[](2);
    andChildren[0] = 1;
    andChildren[1] = 2;
    nodes[0] = _createNode(andChildren, OR);

    IntentData memory intentData = _getIntentData(withPermit, nodes);

    _setUpMainAddress(intentData, false, uniV4TokenId, !withPermit);

    ActionData memory actionData = _getActionData(liquidity);

    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData.coreData, actionData);

    vm.startPrank(caller);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function test_RemoveSuccess_TimeBased(bool withPermit) public {
    Node[] memory nodes = new Node[](3);
    nodes[1] = _createLeafNode(_createYieldCondition(false));
    nodes[2] = _createLeafNode(_createTimeCondition(true));
    uint256[] memory andChildren = new uint256[](2);
    andChildren[0] = 1;
    andChildren[1] = 2;
    nodes[0] = _createNode(andChildren, OR);

    IntentData memory intentData = _getIntentData(withPermit, nodes);

    _setUpMainAddress(intentData, false, uniV4TokenId, !withPermit);

    ActionData memory actionData = _getActionData(liquidity);

    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData.coreData, actionData);

    vm.startPrank(caller);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function test_executeSignedIntent_RemoveSuccess() public {
    IntentData memory intentData = _getIntentData(true, new Node[](0));
    _setUpMainAddress(intentData, true, uniV4TokenId, false);
    ActionData memory actionData = _getActionData(liquidity);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData.coreData, actionData);

    bytes memory maSignature = _getMASignature(intentData);

    vm.startPrank(caller);
    router.executeWithSignedIntent(
      intentData, maSignature, dkSignature, guardian, gdSignature, actionData
    );
  }

  function testRevert_validationAfterExecution(uint256 liq) public {
    liq = bound(liq, 0, liquidity);
    IntentData memory intentData = _getIntentData(true, new Node[](0));
    _setUpMainAddress(intentData, false, uniV4TokenId, false);

    magicNumber = NOT_TRANSFER;

    ActionData memory actionData = _getActionData(liq);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData.coreData, actionData);

    vm.startPrank(caller);
    vm.expectRevert(BaseTickBasedRemoveLiquidityHook.NotEnoughFeesReceived.selector);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function testRevert_validationAfterExecution_InvalidOwner(uint256 liq) public {
    liq = bound(liq, 0, liquidity);
    IntentData memory intentData = _getIntentData(true, new Node[](0));
    _setUpMainAddress(intentData, false, uniV4TokenId, false);

    nftOwner = makeAddr('tmp');

    ActionData memory actionData = _getActionData(liq);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData.coreData, actionData);

    vm.startPrank(caller);
    vm.expectRevert(BaseTickBasedRemoveLiquidityHook.InvalidOwner.selector);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function test_RemoveSuccess_Transfer99Percent(uint256 liq) public {
    liq = bound(liq, 0, liquidity);
    IntentData memory intentData = _getIntentData(true, new Node[](0));
    _setUpMainAddress(intentData, false, uniV4TokenId, false);

    magicNumber = 990_000;

    ActionData memory actionData = _getActionData(liq);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData.coreData, actionData);

    vm.startPrank(caller);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function testRevert_Transfer97Percent_NotTakeUnclaimedFees(uint256 liq) public {
    liq = bound(liq, (liquidity * 10) / 100, liquidity);
    IntentData memory intentData = _getIntentData(true, new Node[](0));
    _setUpMainAddress(intentData, false, uniV4TokenId, false);

    magicNumber = 970_000;

    ActionData memory actionData = _getActionData(liq);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData.coreData, actionData);

    vm.startPrank(caller);
    vm.expectRevert(BaseTickBasedRemoveLiquidityHook.NotEnoughOutputAmount.selector);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function testFuzz_OutputAmounts(uint256 liq) public {
    wrapOrUnwrap = bound(liq, 0, 1) == 1;
    liq = bound(liq, (liquidity * 10) / 100, liquidity);
    takeUnclaimedFees = bound(liq, 0, 1) == 1;

    IntentData memory intentData = _getIntentData(true, new Node[](0));
    _setUpMainAddress(intentData, false, uniV4TokenId, false);

    ActionData memory actionData = _getActionData(liq);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData.coreData, actionData);

    vm.startPrank(caller);
    if (takeUnclaimedFees) {
      vm.expectRevert();
    }
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function testFuzz_ClaimFeeOnly(bool takeFees) public {
    takeUnclaimedFees = takeFees;
    IntentData memory intentData = _getIntentData(true, new Node[](0));
    _setUpMainAddress(intentData, false, uniV4TokenId, false);

    ActionData memory actionData = _getActionData(0);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData.coreData, actionData);

    vm.startPrank(caller);
    if (takeUnclaimedFees) {
      vm.expectRevert(BaseTickBasedRemoveLiquidityHook.NotEnoughFeesReceived.selector);
    }
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function _getIntentData(bool withPermit, Node[] memory nodes)
    internal
    view
    returns (IntentData memory intentData)
  {
    KSRemoveLiquidityUniswapV4Hook.RemoveLiquidityHookData memory hookData;
    hookData.nftAddresses = new address[](1);
    hookData.nftAddresses[0] = pm;
    hookData.nftIds = new uint256[](1);
    hookData.nftIds[0] = uniV4TokenId;
    hookData.maxFees = new uint256[](1);
    hookData.maxFees[0] = (maxFeePercents << 128) | maxFeePercents;

    hookData.nodes = new Node[][](1);
    if (nodes.length > 0) {
      hookData.nodes[0] = nodes;
    } else {
      // Tree structure:
      //          OR (index 0)
      //         /            \
      //    AND (1)          AND (2)
      //    /     \          /     \
      //   A(3)   B(4)     C(5)   D(6)
      //  true   false     true   true
      // Create leaf conditions
      Condition memory conditionA = _createYieldCondition(true);
      Condition memory conditionB = _createTimeCondition(false);
      Condition memory conditionC = _createPriceCondition(true);
      Condition memory conditionD = _createTimeCondition(true);

      nodes = new Node[](7);
      nodes[3] = _createLeafNode(conditionA); // A (true)
      nodes[4] = _createLeafNode(conditionB); // B (false)
      nodes[5] = _createLeafNode(conditionC); // C (true)
      nodes[6] = _createLeafNode(conditionD); // D (true)

      // Create AND nodes
      uint256[] memory andChildren1 = new uint256[](2);
      andChildren1[0] = 3; // A
      andChildren1[1] = 4; // B
      nodes[1] = _createNode(andChildren1, AND); // A AND B (false)

      uint256[] memory andChildren2 = new uint256[](2);
      andChildren2[0] = 5; // C
      andChildren2[1] = 6; // D
      nodes[2] = _createNode(andChildren2, AND); // C AND D (true)

      // Create root OR node
      uint256[] memory orChildren = new uint256[](2);
      orChildren[0] = 1; // A AND B
      orChildren[1] = 2; // C AND D
      nodes[0] = _createNode(orChildren, OR); // (A AND B) OR (C AND D)

      hookData.nodes[0] = nodes;
    }

    hookData.recipient = mainAddress;

    address[] memory actionContracts = new address[](2);
    actionContracts[0] = address(mockActionContract);
    actionContracts[1] = address(pm);

    bytes4[] memory actionSelectors = new bytes4[](2);
    actionSelectors[0] = MockActionContract.removeUniswapV4.selector;
    actionSelectors[1] = IUniswapV3PM.multicall.selector;

    IntentCoreData memory coreData = IntentCoreData({
      mainAddress: mainAddress,
      signatureVerifier: address(0),
      delegatedKey: delegatedPublicKey,
      actionContracts: actionContracts,
      actionSelectors: actionSelectors,
      hook: address(rmLqHook),
      hookIntentData: abi.encode(hookData)
    });

    bytes memory permitData;
    if (withPermit) {
      permitData = _getPermitData(uniV4TokenId);
    }

    TokenData memory tokenData;
    tokenData.erc721Data = new ERC721Data[](1);
    tokenData.erc721Data[0] = ERC721Data({token: pm, tokenId: uniV4TokenId, permitData: permitData});

    intentData = IntentData({coreData: coreData, tokenData: tokenData, extraData: ''});
  }

  function callLibrary(ConditionTree calldata tree, uint256 curIndex) external view returns (bool) {
    return ConditionTreeLibrary.evaluateConditionTree(tree, curIndex, evaluateCondition);
  }

  function evaluateCondition(Condition calldata condition, bytes calldata additionalData)
    public
    view
    returns (bool)
  {
    return rmLqHook.evaluateCondition(condition, additionalData);
  }

  function _getActionData(uint256 _liquidity) internal view returns (ActionData memory actionData) {
    MockActionContract.RemoveUniswapV4Params memory params = MockActionContract.RemoveUniswapV4Params({
      posManager: IPositionManager(pm),
      tokenId: uniV4TokenId,
      admin: address(router),
      nftOwner: nftOwner,
      token0: token0,
      token1: token1,
      liquidity: _liquidity,
      transferPercent: magicNumber,
      wrapOrUnwrap: wrapOrUnwrap,
      weth: weth,
      takeFees: takeUnclaimedFees
    });

    FeeInfo memory feeInfo;
    {
      feeInfo.protocolRecipient = protocolRecipient;
      feeInfo.partnerFeeConfigs = new FeeConfig[][](2);
      feeInfo.partnerFeeConfigs[0] = _buildPartnersConfigs(
        PartnersFeeConfigBuildParams({
          feeModes: [false].toMemoryArray(),
          partnerFees: [uint24(1e6)].toMemoryArray(),
          partnerRecipients: [partnerRecipient].toMemoryArray()
        })
      );

      feeInfo.partnerFeeConfigs[1] = feeInfo.partnerFeeConfigs[0];
    }

    actionData = ActionData({
      erc20Ids: new uint256[](0),
      erc20Amounts: new uint256[](0),
      erc721Ids: [uint256(0)].toMemoryArray(),
      feeInfo: feeInfo,
      approvalFlags: type(uint256).max,
      actionSelectorId: 0,
      actionCalldata: abi.encode(params),
      hookActionData: abi.encode(
        0, fee0, fee1, _liquidity, wrapOrUnwrap, (intentFeesPercent0 << 128) | intentFeesPercent1
      ),
      extraData: '',
      deadline: block.timestamp + 1 days,
      nonce: 0
    });
  }

  function _setUpMainAddress(
    IntentData memory intentData,
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
    fuzzStruct.seed = bound(fuzzStruct.seed, 0, type(uint128).max);
    fuzzStruct.liquidityToRemove = bound(fuzzStruct.liquidityToRemove, 0, liquidity);
    maxFeePercents = bound(maxFeePercents, 0, type(uint128).max);
    fuzzStruct.maxFeePercents = maxFeePercents;

    (uint256 received0, uint256 received1,,) = IPositionManager(pm).poolManager()
      .computePositionValues(IPositionManager(pm), uniV4TokenId, liquidity);

    amount0 = received0;
    amount1 = received1;

    uint256 typeUint = bound(uint256(ConditionType.unwrap(fuzzStruct.conditionType)), 0, 2);
    if (typeUint == 0) {
      fuzzStruct.conditionType = YIELD_BASED;
    } else if (typeUint == 1) {
      fuzzStruct.conditionType = PRICE_BASED;
    } else {
      fuzzStruct.conditionType = TIME_BASED;
    }
  }

  function buildConditionTree(
    Node[] calldata nodes,
    uint256 fee0Collected,
    uint256 fee1Collected,
    uint160 sqrtPriceX96
  ) external pure returns (ConditionTree memory conditionTree) {
    conditionTree.nodes = nodes;
    conditionTree.additionalData = new bytes[](nodes.length);
    for (uint256 i; i < nodes.length; ++i) {
      if (!nodes[i].isLeaf() || nodes[i].condition.isType(TIME_BASED)) {
        continue;
      }
      if (nodes[i].condition.isType(YIELD_BASED)) {
        conditionTree.additionalData[i] = abi.encode(fee0Collected, fee1Collected, sqrtPriceX96);
      } else if (nodes[i].condition.isType(PRICE_BASED)) {
        conditionTree.additionalData[i] = abi.encode(sqrtPriceX96);
      }
    }
  }

  function _randomNodes(FuzzStruct memory fuzzStruct) internal returns (Node[] memory nodes) {
    uint256 maxDepth = bound(fuzzStruct.seed, 1, 10);
    uint256 maxChildren = bound(fuzzStruct.seed, 1, 10);
    uint256 curIndex = 0;

    (Node memory curNode, bool isLeaf) = _buildRandomNode(fuzzStruct, false);
    _nodes.push(curNode);
    _isLeaf[0] = isLeaf;

    for (uint256 i = 0; i < maxDepth; i++) {
      uint256 childrenLength = bound(fuzzStruct.seed, 1, maxChildren);
      curNode = _nodes[curIndex];

      if (_isLeaf[curIndex]) {
        // leaf node
        continue;
      }

      for (uint256 j = 1; j <= childrenLength; j++) {
        (Node memory childNode, bool childIsLeaf) = _buildRandomNode(fuzzStruct, i == maxDepth - 1);

        uint256 childIndex = _nodes.length;
        _nodes.push(childNode);
        _isLeaf[childIndex] = childIsLeaf;
        _nodes[curIndex].childrenIndexes.push(childIndex);
      }
      curIndex++;
    }

    nodes = _nodes;
  }

  function _buildRandomNode(FuzzStruct memory fuzzStruct, bool mustBeLeaf)
    internal
    view
    returns (Node memory, bool isLeaf)
  {
    isLeaf = bound(fuzzStruct.seed, 0, 1) == 1;
    if (mustBeLeaf || isLeaf) {
      Condition memory condition = _createCondition(fuzzStruct);
      return (_createLeafNode(condition), true);
    } else {
      OperationType opType = (fuzzStruct.seed << 1) % 3 == 0 ? AND : OR;
      return (_createNode(new uint256[](0), opType), false);
    }
  }

  function _createLeafNode(Condition memory condition) internal pure returns (Node memory) {
    uint256[] memory emptyChildren = new uint256[](0);
    return Node({
      operationType: AND, // doesn't matter for leaf
      condition: condition,
      childrenIndexes: emptyChildren
    });
  }

  function _createNode(uint256[] memory children, OperationType opType)
    internal
    pure
    returns (Node memory)
  {
    Condition memory emptyCondition = Condition({conditionType: TIME_BASED, data: ''});
    return Node({
      operationType: opType,
      condition: emptyCondition, // doesn't matter for non-leaf
      childrenIndexes: children
    });
  }

  function _createCondition(FuzzStruct memory fuzzStruct) internal view returns (Condition memory) {
    if (ConditionType.unwrap(fuzzStruct.conditionType) == ConditionType.unwrap(YIELD_BASED)) {
      return _createYieldCondition(fuzzStruct.conditionPass);
    } else if (ConditionType.unwrap(fuzzStruct.conditionType) == ConditionType.unwrap(PRICE_BASED))
    {
      return _createPriceCondition(fuzzStruct.conditionPass);
    } else {
      return _createTimeCondition(fuzzStruct.conditionPass);
    }
  }

  function _createYieldCondition(bool isTrue) internal view returns (Condition memory condition) {
    condition.conditionType = YIELD_BASED;

    if (isTrue) {
      condition.data = abi.encode(
        YieldCondition({
          targetYield: 1000, // 0.1%
          initialAmounts: (uint256(amount0) << 128) | uint256(amount1)
        })
      );
    } else {
      condition.data = abi.encode(
        YieldCondition({
          targetYield: 10_000_000, // 1000%
          initialAmounts: (uint256(amount0) << 128) | uint256(amount1)
        })
      );
    }
  }

  function _createTimeCondition(bool isTrue) internal view returns (Condition memory) {
    TimeCondition memory timeCondition = TimeCondition({
      startTimestamp: isTrue ? block.timestamp - 100 : block.timestamp + 100,
      endTimestamp: isTrue ? block.timestamp + 100 : block.timestamp + 200
    });

    return Condition({conditionType: TIME_BASED, data: abi.encode(timeCondition)});
  }

  function _createPriceCondition(bool isTrue) internal view returns (Condition memory) {
    PriceCondition memory priceCondition;
    if (isTrue) {
      priceCondition.minPrice = currentPrice - 100;
      priceCondition.maxPrice = currentPrice + 100;
    } else {
      priceCondition.minPrice = currentPrice + 100;
      priceCondition.maxPrice = currentPrice + 1000;
    }

    return Condition({conditionType: PRICE_BASED, data: abi.encode(priceCondition)});
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
