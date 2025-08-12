// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.t.sol';

import 'src/hooks/base/BaseConditionalHook.sol';
import {Actions} from 'src/interfaces/pancakev4/Types.sol';

import {
  ActionData,
  BaseTickBasedRemoveLiquidityHook,
  CLPositionInfo,
  ICLPositionManager,
  IntentCoreData,
  KSRemoveLiquidityPancakeV4CLHook,
  PoolId,
  PoolKey as PKey,
  TickInfo,
  TokenData
} from 'src/hooks/remove-liq/KSRemoveLiquidityPancakeV4CLHook.sol';
import {ICLPoolManager} from 'src/interfaces/pancakev4/ICLPositionManager.sol';
import 'src/libraries/uniswapv4/LiquidityAmounts.sol';
import 'src/libraries/uniswapv4/TickMath.sol';
import 'test/common/Permit.sol';

contract RemoveLiquidityPancakeV4CLTest is BaseTest {
  using SafeERC20 for IERC20;
  using TokenHelper for address;

  ICLPositionManager positionManager =
    ICLPositionManager(0x55f4c8abA71A1e923edC303eb4fEfF14608cC226);
  ICLPoolManager clPoolManager = ICLPoolManager(0xa0FfB9c1CE1Fe56963B0321B32E7A0302114058b);
  uint256 tokenId = 19_253;
  address token0 = TokenHelper.NATIVE_ADDRESS;
  address token1 = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
  int24 tickLower;
  int24 tickUpper;
  int24 currentTick;
  uint160 currentPrice;
  uint256 liquidity;
  address tokenOwner;
  address wbnb = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
  uint256 maxFeePercents = 20_000; // 2%
  uint256 transferPercent = 1_000_000; // 100%
  uint256 intentFeesPercent0 = 10_000; // 1%
  uint256 intentFeesPercent1 = 10_000; // 1%
  uint256[2] amounts;
  uint256[2] fees;
  bool takeUnclaimedFees;
  bool wrapOrUnwrap;
  ConditionType constant TIME_BASED = ConditionType.wrap(keccak256('TIME_BASED'));
  ConditionType constant PRICE_BASED = ConditionType.wrap(keccak256('PRICE_BASED'));
  ConditionType constant YIELD_BASED = ConditionType.wrap(keccak256('YIELD_BASED'));
  OperationType constant AND = OperationType.AND;
  OperationType constant OR = OperationType.OR;
  Node[] internal _nodes;
  mapping(uint256 => bool) internal _isLeaf;
  uint256 public constant Q128 = 1 << 128;

  KSRemoveLiquidityPancakeV4CLHook rmLqValidator;
  KSRemoveLiquidityPancakeV4CLHook.PancakeV4CLParams pancakeCL;

  struct FuzzStruct {
    uint256 seed;
    uint256 liquidityToRemove;
    bool usePermit;
    bool withSignedIntent;
    ConditionType conditionType;
    bool conditionPass;
    bool positionOutRange;
    uint256 maxFeePercents;
  }

  function setUp() public override {
    super.setUp();

    {
      vm.startPrank(admin);
      address[] memory actionContracts = new address[](2);
      actionContracts[0] = address(positionManager);
      router.whitelistActionContracts(actionContracts, true);
      vm.stopPrank();
    }

    vm.label(token0, 'BNB');
    vm.label(token1, 'CAKE');
    vm.label(address(positionManager), 'CLPositionManager');

    rmLqValidator = new KSRemoveLiquidityPancakeV4CLHook(wbnb);
    address[] memory validators = new address[](1);
    validators[0] = address(rmLqValidator);
    PKey memory poolKey;
    (
      poolKey,
      tickLower,
      tickUpper,
      liquidity,
      pancakeCL.removeLiqParams.positionInfo.feesGrowthInsideLast[0],
      pancakeCL.removeLiqParams.positionInfo.feesGrowthInsideLast[1],
    ) = positionManager.positions(tokenId);
    pancakeCL.poolId = _toId(poolKey);
    pancakeCL.clPoolManager = clPoolManager;
    pancakeCL.removeLiqParams.positionInfo.liquidity = liquidity;
    (pancakeCL.removeLiqParams.sqrtPriceX96, pancakeCL.removeLiqParams.currentTick,,) =
      pancakeCL.clPoolManager.getSlot0(pancakeCL.poolId);

    pancakeCL.removeLiqParams.positionInfo.ticks[0] = tickLower;
    pancakeCL.removeLiqParams.positionInfo.ticks[1] = tickUpper;
    currentPrice = uint160(pancakeCL.removeLiqParams.sqrtPriceX96);
    currentTick = pancakeCL.removeLiqParams.currentTick;
    pancakeCL.outputParams.maxFees = [maxFeePercents, maxFeePercents];

    tokenOwner = positionManager.ownerOf(tokenId);
    vm.prank(tokenOwner);
    positionManager.safeTransferFrom(tokenOwner, mainAddress, tokenId);
    tokenOwner = mainAddress;
  }

  function _selectFork() public virtual override {
    vm.createSelectFork('bsc_mainnet', 56_756_230);
  }

  function testFuzz_RemoveLiquidityPancakeV4CL(FuzzStruct memory fuzz) public {
    _boundStruct(fuzz);
    _computePositionValues();
    fuzz.positionOutRange = true;
    if (fuzz.positionOutRange) {
      _overrideParams();
      _computePositionValues();
    }

    amounts = pancakeCL.removeLiqParams.positionInfo.amounts;
    fees = pancakeCL.removeLiqParams.positionInfo.unclaimedFees;

    Node[] memory nodes = _randomNodes(fuzz);
    ConditionTree memory conditionTree =
      this.buildConditionTree(nodes, fees[0], fees[1], currentPrice);
    bool conditionPass = this.callLibrary(conditionTree, 0);

    IntentData memory intentData = _getIntentData(fuzz.usePermit, nodes);

    _setUpMainAddress(intentData, false, tokenId, true);

    ActionData memory actionData =
      _getActionData(intentData.tokenData, pancakeCL.removeLiqParams.liquidityToRemove);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    uint256 balance0Before = token0.balanceOf(mainAddress);
    uint256 balance1Before = token1.balanceOf(mainAddress);

    vm.startPrank(caller);
    if (conditionPass) {
      router.execute(intentData, daSignature, guardian, gdSignature, actionData);
    } else {
      vm.expectRevert(IKSConditionalHook.ConditionsNotMet.selector);
      router.execute(intentData, daSignature, guardian, gdSignature, actionData);
    }

    if (conditionPass) {
      uint256 balance0After = token0.balanceOf(mainAddress);
      uint256 balance1After = token1.balanceOf(mainAddress);
      uint256 intentFee0 =
        pancakeCL.removeLiqParams.positionInfo.amounts[0] * intentFeesPercent0 / 1_000_000;
      uint256 intentFee1 =
        pancakeCL.removeLiqParams.positionInfo.amounts[1] * intentFeesPercent1 / 1_000_000;
      assertEq(
        balance0After - balance0Before,
        pancakeCL.removeLiqParams.positionInfo.amounts[0] - intentFee0
          + pancakeCL.removeLiqParams.positionInfo.unclaimedFees[0],
        'invalid token0 received'
      );
      assertEq(
        balance1After - balance1Before,
        pancakeCL.removeLiqParams.positionInfo.amounts[1] - intentFee1
          + pancakeCL.removeLiqParams.positionInfo.unclaimedFees[1],
        'invalid token1 received'
      );
    }
  }

  function test_multiCallToPancakeV4CLPositionManager(uint256 seed) public {
    bool unwrap = seed % 2 == 1;
    pancakeCL.removeLiqParams.liquidityToRemove = bound(seed, 0, liquidity);
    _computePositionValues();

    bytes[] memory multiCalldata;
    if (!unwrap) {
      bytes memory actions = new bytes(2);
      bytes[] memory params = new bytes[](2);
      actions[0] = bytes1(uint8(Actions.CL_DECREASE_LIQUIDITY));
      params[0] = abi.encode(tokenId, pancakeCL.removeLiqParams.liquidityToRemove, 0, 0, '');
      actions[1] = bytes1(uint8(Actions.TAKE_PAIR));
      params[1] = abi.encode(address(0), token1, address(router));

      multiCalldata = new bytes[](2);
      multiCalldata[0] = abi.encodeWithSelector(
        ICLPositionManager.modifyLiquidities.selector,
        abi.encode(actions, params),
        type(uint256).max
      );
      multiCalldata[1] = abi.encodeWithSelector(
        IERC721.transferFrom.selector, address(forwarder), mainAddress, tokenId
      );
    } else {
      bytes memory actions = new bytes(5);
      bytes[] memory params = new bytes[](5);
      actions[0] = bytes1(uint8(Actions.CL_DECREASE_LIQUIDITY));
      params[0] = abi.encode(tokenId, pancakeCL.removeLiqParams.liquidityToRemove, 0, 0, '');
      actions[1] = bytes1(uint8(Actions.TAKE_PAIR));
      params[1] = abi.encode(address(0), token1, address(positionManager));
      actions[2] = bytes1(uint8(Actions.WRAP));

      uint256 amount = 0x8000000000000000000000000000000000000000000000000000000000000000; //contract balance
      params[2] = abi.encode(amount);
      actions[3] = bytes1(uint8(Actions.SWEEP));
      params[3] = abi.encode(wbnb, address(router));
      actions[4] = bytes1(uint8(Actions.SWEEP));
      params[4] = abi.encode(token1, address(router));

      multiCalldata = new bytes[](2);
      multiCalldata[0] = abi.encodeWithSelector(
        ICLPositionManager.modifyLiquidities.selector,
        abi.encode(actions, params),
        type(uint256).max
      );
      multiCalldata[1] = abi.encodeWithSelector(
        IERC721.transferFrom.selector, address(forwarder), mainAddress, tokenId
      );
    }

    IntentData memory intentData = _getIntentData(false, new Node[](0));

    _setUpMainAddress(intentData, false, tokenId, true);

    ActionData memory actionData = ActionData({
      tokenData: intentData.tokenData,
      actionSelectorId: 1,
      approvalFlags: type(uint256).max,
      actionCalldata: abi.encode(multiCalldata),
      hookActionData: abi.encode(
        0,
        pancakeCL.removeLiqParams.positionInfo.unclaimedFees[0],
        pancakeCL.removeLiqParams.positionInfo.unclaimedFees[1],
        pancakeCL.removeLiqParams.liquidityToRemove,
        unwrap,
        intentFeesPercent0 << 128 | intentFeesPercent1
      ),
      extraData: '',
      deadline: block.timestamp + 1 days,
      nonce: 0
    });

    if (unwrap) {
      token0 = wbnb;
    }

    address feeRecipient = router.feeRecipient();

    uint256[2] memory feeBefore = [token0.balanceOf(feeRecipient), token1.balanceOf(feeRecipient)];
    uint256[2] memory mainAddrBefore =
      [token0.balanceOf(mainAddress), token1.balanceOf(mainAddress)];

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    vm.expectEmit(false, false, false, true, address(rmLqValidator));
    emit BaseTickBasedRemoveLiquidityHook.LiquidityRemoved(
      address(positionManager), tokenId, pancakeCL.removeLiqParams.liquidityToRemove
    );
    router.execute(intentData, daSignature, guardian, gdSignature, actionData);

    uint256 intentFee0 =
      pancakeCL.removeLiqParams.positionInfo.amounts[0] * intentFeesPercent0 / 1e6;
    uint256 intentFee1 =
      pancakeCL.removeLiqParams.positionInfo.amounts[1] * intentFeesPercent1 / 1e6;

    uint256 received0 = pancakeCL.removeLiqParams.positionInfo.amounts[0]
      + pancakeCL.removeLiqParams.positionInfo.unclaimedFees[0] - intentFee0;
    uint256 received1 = pancakeCL.removeLiqParams.positionInfo.amounts[1]
      + pancakeCL.removeLiqParams.positionInfo.unclaimedFees[1] - intentFee1;

    uint256[2] memory feeAfter = [token0.balanceOf(feeRecipient), token1.balanceOf(feeRecipient)];

    assertEq(feeAfter[0] - feeBefore[0], intentFee0, 'invalid intent fee 0');
    assertEq(feeAfter[1] - feeBefore[1], intentFee1, 'invalid token1 fee 1');

    uint256[2] memory mainAddrAfter = [token0.balanceOf(mainAddress), token1.balanceOf(mainAddress)];

    assertEq(mainAddrAfter[0] - mainAddrBefore[0], received0, 'invalid token0 received');
    assertEq(mainAddrAfter[1] - mainAddrBefore[1], received1, 'invalid token1 received');
  }

  function testFuzz_ValidateOutputPancakeV4CL(
    uint256 liquidityToRemove,
    bool wrap,
    bool takeFees,
    uint256 intentFees0,
    uint256 intentFees1
  ) public {
    pancakeCL.removeLiqParams.liquidityToRemove =
      bound(liquidityToRemove, 0, pancakeCL.removeLiqParams.positionInfo.liquidity);
    wrapOrUnwrap = wrap;
    takeUnclaimedFees = takeFees;
    intentFeesPercent0 = bound(intentFees0, 0, 1_000_000);
    intentFeesPercent1 = bound(intentFees1, 0, 1_000_000);

    _computePositionValues();

    amounts = pancakeCL.removeLiqParams.positionInfo.amounts;
    fees = pancakeCL.removeLiqParams.positionInfo.unclaimedFees;

    IntentData memory intentData = _getIntentData(wrap, new Node[](0));

    _setUpMainAddress(intentData, false, tokenId, !wrap);

    ActionData memory actionData =
      _getActionData(intentData.tokenData, pancakeCL.removeLiqParams.liquidityToRemove);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    // always success when dont charge fees on the user's unclaimed fees
    if (pancakeCL.removeLiqParams.liquidityToRemove == 0 && !takeUnclaimedFees) {
      router.execute(intentData, daSignature, guardian, gdSignature, actionData);
      return;
    }

    uint256 minReceived0 =
      (amounts[0] * (1_000_000 - pancakeCL.outputParams.maxFees[0])) / 1_000_000 + fees[0];
    uint256 minReceived1 =
      (amounts[1] * (1_000_000 - pancakeCL.outputParams.maxFees[1])) / 1_000_000 + fees[1];

    uint256 actualReceived0 = amounts[0] + fees[0];
    uint256 actualReceived1 = amounts[1] + fees[1];

    if (takeUnclaimedFees) {
      actualReceived0 -= fees[0];
      actualReceived1 -= fees[1];
    }

    if (actualReceived0 < fees[0] || actualReceived1 < fees[1]) {
      vm.startPrank(caller);
      vm.expectRevert(BaseTickBasedRemoveLiquidityHook.NotEnoughFeesReceived.selector);
      router.execute(intentData, daSignature, guardian, gdSignature, actionData);
      return;
    }

    uint256 amount0ReceivedForLiquidity = actualReceived0 - fees[0];
    uint256 amount1ReceivedForLiquidity = actualReceived1 - fees[1];

    uint256 intentFee0 = amount0ReceivedForLiquidity * intentFeesPercent0 / 1e6;
    uint256 intentFee1 = amount1ReceivedForLiquidity * intentFeesPercent1 / 1e6;

    actualReceived0 -= intentFee0;
    actualReceived1 -= intentFee1;

    if (wrapOrUnwrap) {
      token0 = wbnb;
    }

    uint256 balance0Before = token0.balanceOf(mainAddress);
    uint256 balance1Before = token1.balanceOf(mainAddress);

    vm.startPrank(caller);
    if (actualReceived0 < minReceived0 || actualReceived1 < minReceived1) {
      vm.expectRevert(BaseTickBasedRemoveLiquidityHook.NotEnoughOutputAmount.selector);
      router.execute(intentData, daSignature, guardian, gdSignature, actionData);
      return;
    }

    router.execute(intentData, daSignature, guardian, gdSignature, actionData);

    uint256 balance0After = token0.balanceOf(mainAddress);
    uint256 balance1After = token1.balanceOf(mainAddress);

    assertEq(balance0After - balance0Before, actualReceived0, 'invalid token0 received');
    assertEq(balance1After - balance1Before, actualReceived1, 'invalid token1 received');
  }

  function _getIntentData(bool withPermit, Node[] memory nodes)
    internal
    view
    returns (IntentData memory intentData)
  {
    KSRemoveLiquidityPancakeV4CLHook.RemoveLiquidityHookData memory validationData;
    validationData.nftAddresses = new address[](1);
    validationData.nftAddresses[0] = address(positionManager);
    validationData.nftIds = new uint256[](1);
    validationData.nftIds[0] = tokenId;
    validationData.maxFees = new uint256[](1);
    validationData.maxFees[0] = (maxFeePercents << 128) | maxFeePercents;

    validationData.nodes = new Node[][](1);
    if (nodes.length > 0) {
      validationData.nodes[0] = nodes;
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

      validationData.nodes[0] = nodes;
    }

    validationData.recipient = mainAddress;

    address[] memory actionContracts = new address[](2);
    actionContracts[0] = address(mockActionContract);
    actionContracts[1] = address(positionManager);

    bytes4[] memory actionSelectors = new bytes4[](2);
    actionSelectors[0] = MockActionContract.removePancakeV4CL.selector;
    actionSelectors[1] = IUniswapV3PM.multicall.selector;

    IntentCoreData memory coreData = IntentCoreData({
      mainAddress: mainAddress,
      delegatedAddress: delegatedAddress,
      actionContracts: actionContracts,
      actionSelectors: actionSelectors,
      hook: address(rmLqValidator),
      hookIntentData: abi.encode(validationData)
    });

    bytes memory permitData;
    if (withPermit) {
      permitData = _getPermitData(tokenId);
    }

    TokenData memory tokenData;
    tokenData.erc721Data = new ERC721Data[](1);
    tokenData.erc721Data[0] =
      ERC721Data({token: address(positionManager), tokenId: tokenId, permitData: permitData});

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
    return rmLqValidator.evaluateCondition(condition, additionalData);
  }

  function _getActionData(TokenData memory tokenData, uint256 _liquidity)
    internal
    returns (ActionData memory actionData)
  {
    MockActionContract.RemovePancakeV4CLParams memory params = MockActionContract
      .RemovePancakeV4CLParams({
      pm: ICLPositionManager(positionManager),
      tokenId: tokenId,
      router: address(router),
      owner: tokenOwner,
      token0: token0,
      token1: token1,
      liquidity: _liquidity,
      transferPercent: transferPercent,
      wrapOrUnwrap: wrapOrUnwrap,
      weth: wbnb,
      takeFees: takeUnclaimedFees,
      amounts: amounts,
      fees: fees
    });
    actionData = ActionData({
      tokenData: tokenData,
      actionSelectorId: 0,
      approvalFlags: type(uint256).max,
      actionCalldata: abi.encode(params),
      hookActionData: abi.encode(
        0, fees[0], fees[1], _liquidity, wrapOrUnwrap, intentFeesPercent0 << 128 | intentFeesPercent1
      ),
      extraData: '',
      deadline: block.timestamp + 1 days,
      nonce: 0
    });
  }

  function _setUpMainAddress(
    IntentData memory intentData,
    bool withSignedIntent,
    uint256 id,
    bool needApproval
  ) internal {
    vm.startPrank(mainAddress);
    if (!withSignedIntent) {
      router.delegate(intentData);
    }
    if (needApproval) {
      positionManager.approve(address(router), id);
    }
    vm.stopPrank();
  }

  function _getPermitData(uint256 id) internal view returns (bytes memory permitData) {
    bytes32 digest = Permit.uniswapV4Permit(
      address(positionManager), address(router), id, 0, block.timestamp + 1 days
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(mainAddressKey, digest);
    bytes memory signature = abi.encodePacked(r, s, v);

    permitData = abi.encode(block.timestamp + 1 days, 0, signature);
  }

  function _boundStruct(FuzzStruct memory fuzzStruct) internal {
    fuzzStruct.seed = bound(fuzzStruct.seed, 0, type(uint128).max);
    pancakeCL.removeLiqParams.liquidityToRemove = bound(fuzzStruct.liquidityToRemove, 0, liquidity);
    maxFeePercents = bound(maxFeePercents, 0, type(uint128).max);
    fuzzStruct.maxFeePercents = maxFeePercents;

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
          initialAmounts: (uint256(amounts[0]) << 128) | uint256(amounts[1])
        })
      );
    } else {
      condition.data = abi.encode(
        YieldCondition({
          targetYield: 10_000_000, // 1000%
          initialAmounts: (uint256(amounts[0]) << 128) | uint256(amounts[1])
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

  function _computePositionValues() internal {
    if (pancakeCL.removeLiqParams.liquidityToRemove != 0) {
      uint160 sqrtPriceLower =
        TickMath.getSqrtRatioAtTick(pancakeCL.removeLiqParams.positionInfo.ticks[0]);
      uint160 sqrtPriceUpper =
        TickMath.getSqrtRatioAtTick(pancakeCL.removeLiqParams.positionInfo.ticks[1]);
      (
        pancakeCL.removeLiqParams.positionInfo.amounts[0],
        pancakeCL.removeLiqParams.positionInfo.amounts[1]
      ) = LiquidityAmounts.getAmountsForLiquidity(
        pancakeCL.removeLiqParams.sqrtPriceX96,
        sqrtPriceLower,
        sqrtPriceUpper,
        uint128(pancakeCL.removeLiqParams.liquidityToRemove)
      );
    }

    (uint256 feeGrowthInside0, uint256 feeGrowthInside1) = _getFeeGrowthInside();

    unchecked {
      pancakeCL.removeLiqParams.positionInfo.unclaimedFees[0] = Math.mulDiv(
        feeGrowthInside0 - pancakeCL.removeLiqParams.positionInfo.feesGrowthInsideLast[0],
        pancakeCL.removeLiqParams.positionInfo.liquidity,
        Q128
      );
      pancakeCL.removeLiqParams.positionInfo.unclaimedFees[1] = Math.mulDiv(
        feeGrowthInside1 - pancakeCL.removeLiqParams.positionInfo.feesGrowthInsideLast[1],
        pancakeCL.removeLiqParams.positionInfo.liquidity,
        Q128
      );
    }
  }

  function _getFeeGrowthInside()
    internal
    view
    returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128)
  {
    (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) =
      clPoolManager.getFeeGrowthGlobals(pancakeCL.poolId);

    int24 lowerTick = pancakeCL.removeLiqParams.positionInfo.ticks[0];
    int24 upperTick = pancakeCL.removeLiqParams.positionInfo.ticks[1];

    TickInfo memory lower = clPoolManager.getPoolTickInfo(pancakeCL.poolId, lowerTick);
    TickInfo memory upper = clPoolManager.getPoolTickInfo(pancakeCL.poolId, upperTick);

    uint256 feeGrowthBelow0X128;
    uint256 feeGrowthBelow1X128;

    unchecked {
      if (currentTick >= lowerTick) {
        feeGrowthBelow0X128 = lower.feeGrowthOutside0X128;
        feeGrowthBelow1X128 = lower.feeGrowthOutside1X128;
      } else {
        feeGrowthBelow0X128 = feeGrowthGlobal0X128 - lower.feeGrowthOutside0X128;
        feeGrowthBelow1X128 = feeGrowthGlobal1X128 - lower.feeGrowthOutside1X128;
      }

      uint256 feeGrowthAbove0X128;
      uint256 feeGrowthAbove1X128;
      if (currentTick < upperTick) {
        feeGrowthAbove0X128 = upper.feeGrowthOutside0X128;
        feeGrowthAbove1X128 = upper.feeGrowthOutside1X128;
      } else {
        feeGrowthAbove0X128 = feeGrowthGlobal0X128 - upper.feeGrowthOutside0X128;
        feeGrowthAbove1X128 = feeGrowthGlobal1X128 - upper.feeGrowthOutside1X128;
      }

      feeGrowthInside0X128 = feeGrowthGlobal0X128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;
      feeGrowthInside1X128 = feeGrowthGlobal1X128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;
    }
  }

  function _toId(PKey memory poolKey) internal pure returns (PoolId poolId) {
    assembly ("memory-safe") {
      poolId := keccak256(poolKey, 0xc0)
    }
  }

  function _overrideParams() internal {
    tokenId = 19_236; // out range position
    address posOwner = positionManager.ownerOf(tokenId);
    vm.prank(posOwner);
    positionManager.safeTransferFrom(posOwner, mainAddress, tokenId);

    (PKey memory poolKey, CLPositionInfo posInfo) = positionManager.getPoolAndPositionInfo(tokenId);

    (
      poolKey,
      tickLower,
      tickUpper,
      liquidity,
      pancakeCL.removeLiqParams.positionInfo.feesGrowthInsideLast[0],
      pancakeCL.removeLiqParams.positionInfo.feesGrowthInsideLast[1],
    ) = positionManager.positions(tokenId);
    pancakeCL.poolId = _toId(poolKey);
    pancakeCL.clPoolManager = clPoolManager;
    pancakeCL.removeLiqParams.positionInfo.liquidity = liquidity;

    pancakeCL.removeLiqParams.positionInfo.ticks[0] = tickLower;
    pancakeCL.removeLiqParams.positionInfo.ticks[1] = tickUpper;
    pancakeCL.removeLiqParams.liquidityToRemove = liquidity;

    console.log('tickLower', tickLower);
    console.log('tickUpper', tickUpper);
    console.log('currentTick', currentTick);

    assertTrue(currentTick < tickLower || currentTick > tickUpper, 'wrong position');
  }
}

// │   │   └─ ← [Return] [0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c, 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82], [166815920095184 [1.668e14], 66116749457244408 [6.611e16]], [675809484727625387 [6.758e17], 267510419146929393910 [2.675e20]], mainAddress: [0x3674eD9c52D903C6c3A468592Ac27Fe71B3CD849]
