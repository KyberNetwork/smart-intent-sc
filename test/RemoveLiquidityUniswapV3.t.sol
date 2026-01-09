// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.t.sol';
import 'src/hooks/base/BaseConditionalHook.sol';
import 'src/hooks/remove-liq/KSRemoveLiquidityUniswapV3Hook.sol';

import {IERC721} from 'src/interfaces/uniswapv3/IUniswapV3PM.sol';
import 'test/common/Permit.sol';

import 'src/types/ConditionTree.sol';

contract RemoveLiquidityUniswapV3Test is BaseTest {
  using ArraysHelper for *;

  using SafeERC20 for IERC20;
  using TokenHelper for address;

  IUniswapV3PM pm = IUniswapV3PM(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
  IUniswapV3Pool pool = IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
  uint256 tokenId = 963_424;
  address tokenOwner;
  address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  uint256 maxFeePercents = 20_000; // 2%
  uint256 transferPercent = 1_000_000; // 100%
  uint256 intentFeesPercent0 = 10_000; // 1%
  uint256 intentFeesPercent1 = 10_000; // 1%
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

  KSRemoveLiquidityUniswapV3Hook.UniswapV3Params internal uniswapV3;
  KSRemoveLiquidityUniswapV3Hook rmLqValidator;

  function setUp() public override {
    super.setUp();

    rmLqValidator = new KSRemoveLiquidityUniswapV3Hook(weth);
    tokenOwner = pm.ownerOf(tokenId);

    vm.prank(tokenOwner);
    IERC721(pm).safeTransferFrom(tokenOwner, mainAddress, tokenId);
    tokenOwner = mainAddress;

    _cacheInfo();

    vm.prank(admin);
    router.grantRole(ACTION_CONTRACT_ROLE, address(pm));
  }

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

  function _selectFork() public override {
    FORK_BLOCK = 22_230_873;
    vm.createSelectFork('mainnet', FORK_BLOCK);
  }

  function testFuzz_RemoveLiquidityUniswapV3(FuzzStruct memory fuzz) public {
    _boundStruct(fuzz);
    _computePositionValues();
    if (!fuzz.positionOutRange) {
      _overrideParams();
      _computePositionValues();
    }

    uint256[2] memory amounts = uniswapV3.removeLiqParams.positionInfo.amounts;
    uint256[2] memory fees = uniswapV3.removeLiqParams.positionInfo.unclaimedFees;

    Node[] memory nodes = _randomNodes(fuzz);
    ConditionTree memory conditionTree =
      this.buildConditionTree(nodes, fees[0], fees[1], uniswapV3.removeLiqParams.sqrtPriceX96);
    bool conditionPass = this.callLibrary(conditionTree, 0);
    IntentData memory intentData = _getIntentData(nodes);

    _setUpMainAddress(intentData, false, tokenId);

    ActionData memory actionData = _getActionData(uniswapV3.removeLiqParams.liquidityToRemove);

    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData.coreData, actionData);

    uint256 balance0Before = uniswapV3.outputParams.tokens[0].balanceOf(mainAddress);
    uint256 balance1Before = uniswapV3.outputParams.tokens[1].balanceOf(mainAddress);

    vm.startPrank(caller);
    if (conditionPass) {
      router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
    } else {
      vm.expectRevert(IKSConditionalHook.ConditionsNotMet.selector);
      router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
    }

    if (conditionPass) {
      uint256 balance0After = uniswapV3.outputParams.tokens[0].balanceOf(mainAddress);
      uint256 balance1After = uniswapV3.outputParams.tokens[1].balanceOf(mainAddress);
      uint256 intentFee0 = (amounts[0] * intentFeesPercent0) / 1_000_000;
      uint256 intentFee1 = (amounts[1] * intentFeesPercent1) / 1_000_000;
      assertEq(
        balance0After - balance0Before, amounts[0] - intentFee0 + fees[0], 'invalid token0 received'
      );
      assertEq(
        balance1After - balance1Before, amounts[1] - intentFee1 + fees[1], 'invalid token1 received'
      );
    }
  }

  function testFuzz_ValidateAmountOutUniswapV3(
    uint256 liquidityToRemove,
    bool wrap,
    bool takeFees,
    uint256 intentFees0,
    uint256 intentFees1
  ) public {
    uniswapV3.removeLiqParams.liquidityToRemove =
      bound(liquidityToRemove, 0, uniswapV3.removeLiqParams.positionInfo.liquidity);
    wrapOrUnwrap = wrap;
    takeUnclaimedFees = takeFees;
    intentFeesPercent0 = bound(intentFees0, 0, 1_000_000);
    intentFeesPercent1 = bound(intentFees1, 0, 1_000_000);

    _computePositionValues();

    IntentData memory intentData = _getIntentData(new Node[](0));

    _setUpMainAddress(intentData, false, tokenId);

    ActionData memory actionData = _getActionData(uniswapV3.removeLiqParams.liquidityToRemove);

    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData.coreData, actionData);

    // always success when dont charge fees on the user's unclaimed fees
    if (uniswapV3.removeLiqParams.liquidityToRemove == 0 && !takeUnclaimedFees) {
      router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
      return;
    }

    uint256[2] memory amounts = uniswapV3.removeLiqParams.positionInfo.amounts;
    uint256[2] memory fees = uniswapV3.removeLiqParams.positionInfo.unclaimedFees;

    uint256 minReceived0 =
      (amounts[0] * (1_000_000 - uniswapV3.outputParams.maxFees[0])) / 1_000_000 + fees[0];
    uint256 minReceived1 =
      (amounts[1] * (1_000_000 - uniswapV3.outputParams.maxFees[1])) / 1_000_000 + fees[1];

    uint256 actualReceived0 = amounts[0] + fees[0];
    uint256 actualReceived1 = amounts[1] + fees[1];

    if (takeUnclaimedFees) {
      actualReceived0 -= fees[0];
      actualReceived1 -= fees[1];
    }

    if (actualReceived0 < fees[0] || actualReceived1 < fees[1]) {
      vm.startPrank(caller);
      vm.expectRevert(BaseTickBasedRemoveLiquidityHook.NotEnoughFeesReceived.selector);
      router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
      return;
    }

    uint256 amount0ReceivedForLiquidity = actualReceived0 - fees[0];
    uint256 amount1ReceivedForLiquidity = actualReceived1 - fees[1];

    uint256 intentFee0 = (amount0ReceivedForLiquidity * intentFeesPercent0) / 1e6;
    uint256 intentFee1 = (amount1ReceivedForLiquidity * intentFeesPercent1) / 1e6;

    actualReceived0 -= intentFee0;
    actualReceived1 -= intentFee1;

    address token0 = uniswapV3.outputParams.tokens[0];
    address token1 = uniswapV3.outputParams.tokens[1];
    if (wrap) {
      token1 = TokenHelper.NATIVE_ADDRESS;
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

  function test_multiCallToUniV3PositionManager(bool wrap) public {
    wrap = true;
    bytes[] memory multiCalldata;
    if (!wrap) {
      multiCalldata = new bytes[](5);
      multiCalldata[0] = abi.encodeWithSelector(
        IUniswapV3PM.decreaseLiquidity.selector,
        IUniswapV3PM.DecreaseLiquidityParams({
          tokenId: tokenId,
          liquidity: uint128(uniswapV3.removeLiqParams.liquidityToRemove),
          amount0Min: 0,
          amount1Min: 0,
          deadline: block.timestamp + 1 days
        })
      );
      multiCalldata[1] = abi.encodeWithSelector(
        IUniswapV3PM.collect.selector,
        IUniswapV3PM.CollectParams({
          tokenId: tokenId,
          recipient: address(pm),
          amount0Max: type(uint128).max,
          amount1Max: type(uint128).max
        })
      );
      multiCalldata[2] = abi.encodeWithSelector(
        IERC721.transferFrom.selector, address(forwarder), mainAddress, tokenId
      );
      multiCalldata[3] = abi.encodeWithSelector(
        IUniswapV3PM.sweepToken.selector, uniswapV3.outputParams.tokens[0], 0, address(router)
      );
      multiCalldata[4] = abi.encodeWithSelector(
        IUniswapV3PM.sweepToken.selector, uniswapV3.outputParams.tokens[1], 0, address(router)
      );
    } else {
      multiCalldata = new bytes[](5);
      multiCalldata[0] = abi.encodeWithSelector(
        IUniswapV3PM.decreaseLiquidity.selector,
        IUniswapV3PM.DecreaseLiquidityParams({
          tokenId: tokenId,
          liquidity: uint128(uniswapV3.removeLiqParams.liquidityToRemove),
          amount0Min: 0,
          amount1Min: 0,
          deadline: block.timestamp + 1 days
        })
      );
      multiCalldata[1] = abi.encodeWithSelector(
        IUniswapV3PM.collect.selector,
        IUniswapV3PM.CollectParams({
          tokenId: tokenId,
          recipient: address(pm),
          amount0Max: type(uint128).max,
          amount1Max: type(uint128).max
        })
      );
      multiCalldata[2] = abi.encodeWithSelector(
        IERC721.transferFrom.selector, address(forwarder), mainAddress, tokenId
      );
      multiCalldata[3] =
        abi.encodeWithSelector(IUniswapV3PM.unwrapWETH9.selector, 0, address(router));
      multiCalldata[4] = abi.encodeWithSelector(
        IUniswapV3PM.sweepToken.selector, uniswapV3.outputParams.tokens[0], 0, address(router)
      );
    }

    _computePositionValues();

    IntentData memory intentData = _getIntentData(new Node[](0));

    _setUpMainAddress(intentData, false, tokenId);

    FeeInfo memory feeInfo;
    {
      feeInfo.protocolRecipient = protocolRecipient;
      feeInfo.partnerFeeConfigs = new FeeConfig[][](2);
      feeInfo.partnerFeeConfigs[0] = _buildPartnersConfigs(
        PartnersFeeConfigBuildParams({
          feeModes: [false, true].toMemoryArray(),
          partnerFees: [0.25e6, 0.25e6].toMemoryArray(),
          partnerRecipients: [partnerRecipient, makeAddr('partnerRecipient2')].toMemoryArray()
        })
      );

      feeInfo.partnerFeeConfigs[1] = feeInfo.partnerFeeConfigs[0];
    }

    ActionData memory actionData;
    {
      actionData = ActionData({
        erc20Ids: new uint256[](0),
        erc20Amounts: new uint256[](0),
        erc721Ids: [uint256(0)].toMemoryArray(),
        feeInfo: feeInfo,
        actionSelectorId: 1,
        approvalFlags: type(uint256).max,
        actionCalldata: abi.encode(multiCalldata),
        hookActionData: abi.encode(
          0,
          uniswapV3.removeLiqParams.positionInfo.unclaimedFees[0],
          uniswapV3.removeLiqParams.positionInfo.unclaimedFees[1],
          uniswapV3.removeLiqParams.liquidityToRemove,
          wrap,
          (intentFeesPercent0 << 128) | intentFeesPercent1
        ),
        extraData: '',
        deadline: block.timestamp + 1 days,
        nonce: 0
      });
    }

    if (wrap) {
      uniswapV3.outputParams.tokens[1] = TokenHelper.NATIVE_ADDRESS;
    }

    uint256[2] memory feeBefore = [
      uniswapV3.outputParams.tokens[0].balanceOf(partnerRecipient),
      uniswapV3.outputParams.tokens[1].balanceOf(partnerRecipient)
    ];
    uint256[2] memory fee2Before = [
      uniswapV3.outputParams.tokens[0].balanceOf(makeAddr('partnerRecipient2')),
      uniswapV3.outputParams.tokens[1].balanceOf(makeAddr('partnerRecipient2'))
    ];
    uint256[2] memory mainAddrBefore = [
      uniswapV3.outputParams.tokens[0].balanceOf(mainAddress),
      uniswapV3.outputParams.tokens[1].balanceOf(mainAddress)
    ];

    (, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData.coreData, actionData);

    vm.expectEmit(false, false, false, true, address(rmLqValidator));
    emit BaseTickBasedRemoveLiquidityHook.LiquidityRemoved(
      address(pm), tokenId, uniswapV3.removeLiqParams.liquidityToRemove
    );
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);

    uint256 intentFee0 =
      (uniswapV3.removeLiqParams.positionInfo.amounts[0] * intentFeesPercent0) / 1e6;
    uint256 intentFee1 =
      (uniswapV3.removeLiqParams.positionInfo.amounts[1] * intentFeesPercent1) / 1e6;

    uint256[2] memory feeAfter = [
      uniswapV3.outputParams.tokens[0].balanceOf(partnerRecipient),
      uniswapV3.outputParams.tokens[1].balanceOf(partnerRecipient)
    ];

    uint256[2] memory fee2After = [
      uniswapV3.outputParams.tokens[0].balanceOf(makeAddr('partnerRecipient2')),
      uniswapV3.outputParams.tokens[1].balanceOf(makeAddr('partnerRecipient2'))
    ];
    uint256[2] memory protocolAfter = [
      uniswapV3.outputParams.tokens[0].balanceOf(protocolRecipient),
      uniswapV3.outputParams.tokens[1].balanceOf(protocolRecipient)
    ];

    uint256 partnerFee0 = intentFee0 / 4;
    uint256 partnerFee1 = intentFee1 / 4;

    {
      assertEq(feeAfter[0] - feeBefore[0], partnerFee0, 'invalid partner fee 0');
      assertEq(feeAfter[1] - feeBefore[1], partnerFee1, 'invalid partner fee 1');
    }
    // fee mode is true, so no partner fee is collected by protocol recipient
    {
      assertEq(fee2After[0] - fee2Before[0], 0, 'invalid partner fee 0');
      assertEq(fee2After[1] - fee2Before[1], 0, 'invalid partner fee 1');
    }
    assertEq(protocolAfter[0], intentFee0 - partnerFee0, 'invalid protocol fee 0');
    assertEq(protocolAfter[1], intentFee1 - partnerFee1, 'invalid protocol fee 1');

    uint256[2] memory mainAddrAfter = [
      uniswapV3.outputParams.tokens[0].balanceOf(mainAddress),
      uniswapV3.outputParams.tokens[1].balanceOf(mainAddress)
    ];

    {
      uint256 received0 = uniswapV3.removeLiqParams.positionInfo.amounts[0]
        + uniswapV3.removeLiqParams.positionInfo.unclaimedFees[0] - intentFee0;
      uint256 received1 = uniswapV3.removeLiqParams.positionInfo.amounts[1]
        + uniswapV3.removeLiqParams.positionInfo.unclaimedFees[1] - intentFee1;
      assertEq(mainAddrAfter[0] - mainAddrBefore[0], received0, 'invalid token0 received');
      assertEq(mainAddrAfter[1] - mainAddrBefore[1], received1, 'invalid token1 received');
    }

    {
      assertEq(
        uniswapV3.outputParams.tokens[0].balanceOf(address(router)), 0, 'invalid router balance 0'
      );
      assertEq(
        uniswapV3.outputParams.tokens[1].balanceOf(address(router)), 0, 'invalid router balance 1'
      );
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

  function _setUpMainAddress(IntentData memory intentData, bool withSignedIntent, uint256 _tokenId)
    internal
  {
    vm.startPrank(mainAddress);
    if (!withSignedIntent) {
      router.delegate(intentData);
    }
    pm.approve(address(router), _tokenId);
    vm.stopPrank();
  }

  function _getIntentData(Node[] memory nodes)
    internal
    view
    returns (IntentData memory intentData)
  {
    KSRemoveLiquidityUniswapV3Hook.RemoveLiquidityHookData memory hookData;
    hookData.nftAddresses = new address[](1);
    hookData.nftAddresses[0] = address(pm);
    hookData.nftIds = new uint256[](1);
    hookData.nftIds[0] = tokenId;
    hookData.maxFees = new uint256[](1);
    hookData.maxFees[0] = (maxFeePercents << 128) | maxFeePercents;
    hookData.recipient = mainAddress;

    address[] memory pools = new address[](1);
    pools[0] = address(pool);
    hookData.additionalData = abi.encode(pools);

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
    actionSelectors[0] = MockActionContract.removeUniswapV3.selector;
    actionSelectors[1] = IUniswapV3PM.multicall.selector;

    IntentCoreData memory coreData = IntentCoreData({
      mainAddress: mainAddress,
      signatureVerifier: address(0),
      delegatedKey: delegatedPublicKey,
      actionContracts: actionContracts,
      actionSelectors: actionSelectors,
      hook: address(rmLqValidator),
      hookIntentData: abi.encode(hookData)
    });

    TokenData memory tokenData;
    tokenData.erc721Data = new ERC721Data[](1);
    tokenData.erc721Data[0] = ERC721Data({token: address(pm), tokenId: tokenId, permitData: ''});

    intentData = IntentData({coreData: coreData, tokenData: tokenData, extraData: ''});
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

  function _createYieldCondition(bool isTrue) internal view returns (Condition memory condition) {
    condition.conditionType = YIELD_BASED;

    if (isTrue) {
      condition.data = abi.encode(
        YieldCondition({
          targetYield: 10, // 0.001%
          initialAmounts: (uint256(uniswapV3.removeLiqParams.positionInfo.amounts[0]) << 128)
            | uint256(uniswapV3.removeLiqParams.positionInfo.amounts[1])
        })
      );
    } else {
      condition.data = abi.encode(
        YieldCondition({
          targetYield: 10_000_000, // 1000%
          initialAmounts: (uint256(uniswapV3.removeLiqParams.positionInfo.amounts[0]) << 128)
            | uint256(uniswapV3.removeLiqParams.positionInfo.amounts[1])
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
    uint256 currentPrice = uniswapV3.removeLiqParams.sqrtPriceX96;
    if (isTrue) {
      priceCondition.minPrice = currentPrice - 100;
      priceCondition.maxPrice = currentPrice + 1000;
    } else {
      priceCondition.minPrice = currentPrice + 100;
      priceCondition.maxPrice = currentPrice + 1000;
    }

    return Condition({conditionType: PRICE_BASED, data: abi.encode(priceCondition)});
  }

  function _getActionData(uint256 _liquidity) internal view returns (ActionData memory actionData) {
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
      actionSelectorId: 0,
      approvalFlags: type(uint256).max,
      actionCalldata: abi.encode(
        pm,
        tokenId,
        tokenOwner,
        address(router),
        uniswapV3.outputParams.tokens[0],
        uniswapV3.outputParams.tokens[1],
        _liquidity,
        transferPercent,
        wrapOrUnwrap,
        weth,
        takeUnclaimedFees,
        uniswapV3.removeLiqParams.positionInfo.amounts,
        uniswapV3.removeLiqParams.positionInfo.unclaimedFees
      ),
      hookActionData: abi.encode(
        0,
        uniswapV3.removeLiqParams.positionInfo.unclaimedFees[0],
        uniswapV3.removeLiqParams.positionInfo.unclaimedFees[1],
        _liquidity,
        wrapOrUnwrap,
        (intentFeesPercent0 << 128) | intentFeesPercent1
      ),
      extraData: '',
      deadline: block.timestamp + 1 days,
      nonce: 0
    });
  }

  function _computePositionValues() internal {
    _cacheInfo();
    KSRemoveLiquidityUniswapV3Hook.RemoveLiquidityParams storage removeLiqParams =
    uniswapV3.removeLiqParams;
    KSRemoveLiquidityUniswapV3Hook.PositionInfo storage positionInfo = removeLiqParams.positionInfo;

    int24 lower = positionInfo.ticks[0];
    int24 current = removeLiqParams.currentTick;
    int24 upper = positionInfo.ticks[1];

    if (removeLiqParams.liquidityToRemove != 0) {
      uint160 sqrtPriceLower = TickMath.getSqrtRatioAtTick(lower);
      uint160 sqrtPriceUpper = TickMath.getSqrtRatioAtTick(upper);
      (positionInfo.amounts[0], positionInfo.amounts[1]) = LiquidityAmounts.getAmountsForLiquidity(
        removeLiqParams.sqrtPriceX96,
        sqrtPriceLower,
        sqrtPriceUpper,
        uint128(removeLiqParams.liquidityToRemove)
      );
    }

    (uint256 feeGrowthInside0, uint256 feeGrowthInside1) =
      _getFeeGrowthInside(IUniswapV3Pool(uniswapV3.pool), lower, current, upper);

    unchecked {
      positionInfo.unclaimedFees[
        0
      ] += Math.mulDiv(
        feeGrowthInside0 - positionInfo.feesGrowthInsideLast[0], positionInfo.liquidity, Q128
      );
      positionInfo.unclaimedFees[
        1
      ] += Math.mulDiv(
        feeGrowthInside1 - positionInfo.feesGrowthInsideLast[1], positionInfo.liquidity, Q128
      );
    }
  }

  function _getFeeGrowthInside(IUniswapV3Pool univ3pool, int24 lower, int24 current, int24 upper)
    internal
    view
    returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128)
  {
    (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) =
      (univ3pool.feeGrowthGlobal0X128(), univ3pool.feeGrowthGlobal1X128());
    (,, uint256 feeGrowthOutside0X128Lower, uint256 feeGrowthOutside1X128Lower,,,,) =
      univ3pool.ticks(lower);
    (,, uint256 feeGrowthOutside0X128Upper, uint256 feeGrowthOutside1X128Upper,,,,) =
      univ3pool.ticks(upper);

    uint256 feeGrowthBelow0X128;
    uint256 feeGrowthBelow1X128;
    unchecked {
      if (current >= lower) {
        feeGrowthBelow0X128 = feeGrowthOutside0X128Lower;
        feeGrowthBelow1X128 = feeGrowthOutside1X128Lower;
      } else {
        feeGrowthBelow0X128 = feeGrowthGlobal0X128 - feeGrowthOutside0X128Lower;
        feeGrowthBelow1X128 = feeGrowthGlobal1X128 - feeGrowthOutside1X128Lower;
      }

      uint256 feeGrowthAbove0X128;
      uint256 feeGrowthAbove1X128;
      if (current < upper) {
        feeGrowthAbove0X128 = feeGrowthOutside0X128Upper;
        feeGrowthAbove1X128 = feeGrowthOutside1X128Upper;
      } else {
        feeGrowthAbove0X128 = feeGrowthGlobal0X128 - feeGrowthOutside0X128Upper;
        feeGrowthAbove1X128 = feeGrowthGlobal1X128 - feeGrowthOutside1X128Upper;
      }

      feeGrowthInside0X128 = feeGrowthGlobal0X128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;
      feeGrowthInside1X128 = feeGrowthGlobal1X128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;
    }
  }

  function _cacheInfo() internal {
    {
      uniswapV3.pool = address(pool);
      uniswapV3.removeLiqParams.recipient = mainAddress;
      uniswapV3.removeLiqParams.positionInfo.nftId = tokenId;
      uniswapV3.removeLiqParams.positionInfo.nftAddress = address(pm);
    }
    {
      (
        ,,
        uniswapV3.outputParams.tokens[0],
        uniswapV3.outputParams.tokens[1],,
        uniswapV3.removeLiqParams.positionInfo.ticks[0],
        uniswapV3.removeLiqParams.positionInfo.ticks[1],
        uniswapV3.removeLiqParams.positionInfo.liquidity,
        uniswapV3.removeLiqParams.positionInfo.feesGrowthInsideLast[0],
        uniswapV3.removeLiqParams.positionInfo.feesGrowthInsideLast[1],
        uniswapV3.removeLiqParams.positionInfo.unclaimedFees[0],
        uniswapV3.removeLiqParams.positionInfo.unclaimedFees[1]
      ) = pm.positions(tokenId);
    }
    (uniswapV3.removeLiqParams.sqrtPriceX96, uniswapV3.removeLiqParams.currentTick,,,,,) =
      pool.slot0();
    uniswapV3.removeLiqParams.liquidityToRemove = uniswapV3.removeLiqParams.positionInfo.liquidity;
    uniswapV3.outputParams.maxFees = [maxFeePercents, maxFeePercents];
  }

  function _overrideParams() internal {
    tokenId = 963_350; // out range position
    address posOwner = IUniswapV3PM(pm).ownerOf(tokenId);
    vm.prank(posOwner);
    IERC721(pm).safeTransferFrom(posOwner, mainAddress, tokenId);
    _cacheInfo();

    int24 _tickLower = uniswapV3.removeLiqParams.positionInfo.ticks[0];
    int24 _tickUpper = uniswapV3.removeLiqParams.positionInfo.ticks[1];
    int24 _currentTick = uniswapV3.removeLiqParams.currentTick;
    uint256 _liquidity = uniswapV3.removeLiqParams.positionInfo.liquidity;

    assertTrue(_tickLower > _currentTick || _tickUpper < _currentTick);
    assertTrue(_liquidity > 0, '_liquidity > 0');
  }

  function _boundStruct(FuzzStruct memory fuzzStruct) internal {
    fuzzStruct.seed = bound(fuzzStruct.seed, 0, type(uint128).max);
    fuzzStruct.liquidityToRemove =
      bound(fuzzStruct.liquidityToRemove, 0, uniswapV3.removeLiqParams.positionInfo.liquidity);
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
}
