// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.t.sol';
import 'src/hooks/remove-liq/KSRemoveLiquidityUniswapV3Hook.sol';
import 'test/common/Permit.sol';

contract RemoveLiquidityUniswapV3Test is BaseTest {
  using SafeERC20 for IERC20;
  using TokenHelper for address;

  IUniswapV3PM pm = IUniswapV3PM(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
  IUniswapV3Pool pool = IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
  uint256 tokenId = 963_424;
  address token0;
  address token1;
  int24 tickLower;
  int24 tickUpper;
  int24 currentTick;
  uint160 currentPrice;
  uint256 liquidity;
  address tokenOwner;
  address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
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

  KSRemoveLiquidityUniswapV3Hook.UniswapV3Params internal uniswapV3;
  KSRemoveLiquidityUniswapV3Hook rmLqValidator;

  function setUp() public override {
    super.setUp();

    rmLqValidator = new KSRemoveLiquidityUniswapV3Hook(weth);
    tokenOwner = pm.ownerOf(tokenId);

    (currentPrice, currentTick,,,,,) = pool.slot0();
    (,, token0, token1,, tickLower, tickUpper, liquidity,,,,) = pm.positions(tokenId);

    vm.prank(tokenOwner);
    IERC721(pm).safeTransferFrom(tokenOwner, mainAddress, tokenId);
    tokenOwner = mainAddress;

    uniswapV3.pool = address(pool);
    uniswapV3.removeLiqParams.recipient = mainAddress;
    uniswapV3.removeLiqParams.positionInfo.nftId = tokenId;
    uniswapV3.removeLiqParams.positionInfo.nftAddress = address(pm);
    (
      ,
      ,
      uniswapV3.outputParams.tokens[0],
      uniswapV3.outputParams.tokens[1],
      ,
      uniswapV3.removeLiqParams.positionInfo.ticks[0],
      uniswapV3.removeLiqParams.positionInfo.ticks[1],
      ,
      uniswapV3.removeLiqParams.positionInfo.feesGrowthInsideLast[0],
      uniswapV3.removeLiqParams.positionInfo.feesGrowthInsideLast[1],
      uniswapV3.removeLiqParams.positionInfo.unclaimedFees[0],
      uniswapV3.removeLiqParams.positionInfo.unclaimedFees[1]
    ) = pm.positions(tokenId);
    uniswapV3.removeLiqParams.currentTick = currentTick;
    uniswapV3.removeLiqParams.sqrtPriceX96 = currentPrice;
    uniswapV3.removeLiqParams.positionInfo.liquidity = liquidity;
    uniswapV3.removeLiqParams.liquidityToRemove = liquidity;
    uniswapV3.outputParams.maxFees = [maxFeePercents, maxFeePercents];
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

    amounts = uniswapV3.removeLiqParams.positionInfo.amounts;
    fees = uniswapV3.removeLiqParams.positionInfo.unclaimedFees;

    Node[] memory nodes = _randomNodes(fuzz);
    ConditionTree memory conditionTree =
      this.buildConditionTree(nodes, fees[0], fees[1], currentPrice);
    bool conditionPass = this.callLibrary(conditionTree, 0);
    IntentData memory intentData = _getIntentData(nodes);

    _setUpMainAddress(intentData, false, tokenId);

    ActionData memory actionData =
      _getActionData(intentData.tokenData, uniswapV3.removeLiqParams.liquidityToRemove);

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
        uniswapV3.removeLiqParams.positionInfo.amounts[0] * intentFeesPercent0 / 1_000_000;
      uint256 intentFee1 =
        uniswapV3.removeLiqParams.positionInfo.amounts[1] * intentFeesPercent1 / 1_000_000;
      assertEq(
        balance0After - balance0Before,
        uniswapV3.removeLiqParams.positionInfo.amounts[0] - intentFee0
          + uniswapV3.removeLiqParams.positionInfo.unclaimedFees[0],
        'invalid token0 received'
      );
      assertEq(
        balance1After - balance1Before,
        uniswapV3.removeLiqParams.positionInfo.amounts[1] - intentFee1
          + uniswapV3.removeLiqParams.positionInfo.unclaimedFees[1],
        'invalid token1 received'
      );
    }
  }

  function testFuzz_ValidateAmountOutUniswapV3(uint256 seed) public {
    seed = bound(seed, 0, type(uint128).max);
    uniswapV3.removeLiqParams.liquidityToRemove = bound(seed, 0, liquidity);
    wrapOrUnwrap = bound(seed + 1, 0, 1) == 1;
    takeUnclaimedFees = bound(seed + 2, 0, 1) == 1;
    intentFeesPercent0 = bound(seed + 3, 0, 1_000_000);
    intentFeesPercent1 = bound(seed + 4, 0, 1_000_000);

    _computePositionValues();

    amounts = uniswapV3.removeLiqParams.positionInfo.amounts;
    fees = uniswapV3.removeLiqParams.positionInfo.unclaimedFees;

    IntentData memory intentData = _getIntentData(new Node[](0));

    _setUpMainAddress(intentData, false, tokenId);

    ActionData memory actionData =
      _getActionData(intentData.tokenData, uniswapV3.removeLiqParams.liquidityToRemove);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    // always success when dont charge fees on the user's unclaimed fees
    if (uniswapV3.removeLiqParams.liquidityToRemove == 0 && !takeUnclaimedFees) {
      router.execute(intentData, daSignature, guardian, gdSignature, actionData);
      return;
    }

    uint256 minReceived0 = uniswapV3.removeLiqParams.positionInfo.unclaimedFees[0]
      + (
        uniswapV3.removeLiqParams.positionInfo.amounts[0]
          * (1_000_000 - uniswapV3.outputParams.maxFees[0])
      ) / 1_000_000;
    uint256 minReceived1 = uniswapV3.removeLiqParams.positionInfo.unclaimedFees[1]
      + (
        uniswapV3.removeLiqParams.positionInfo.amounts[1]
          * (1_000_000 - uniswapV3.outputParams.maxFees[1])
      ) / 1_000_000;

    uint256 actualReceived0 = uniswapV3.removeLiqParams.positionInfo.amounts[0]
      + uniswapV3.removeLiqParams.positionInfo.unclaimedFees[0];
    uint256 actualReceived1 = uniswapV3.removeLiqParams.positionInfo.amounts[1]
      + uniswapV3.removeLiqParams.positionInfo.unclaimedFees[1];

    uint256 intentFee0 =
      uniswapV3.removeLiqParams.positionInfo.amounts[0] * intentFeesPercent0 / 1e6;
    uint256 intentFee1 =
      uniswapV3.removeLiqParams.positionInfo.amounts[1] * intentFeesPercent1 / 1e6;

    if (takeUnclaimedFees) {
      actualReceived0 -= uniswapV3.removeLiqParams.positionInfo.unclaimedFees[0];
      actualReceived1 -= uniswapV3.removeLiqParams.positionInfo.unclaimedFees[1];
    }

    actualReceived0 -= intentFee0;
    actualReceived1 -= intentFee1;

    vm.startPrank(caller);
    if (
      takeUnclaimedFees
        && (
          uniswapV3.removeLiqParams.positionInfo.amounts[0]
            < uniswapV3.removeLiqParams.positionInfo.unclaimedFees[0]
            || uniswapV3.removeLiqParams.positionInfo.amounts[1]
              < uniswapV3.removeLiqParams.positionInfo.unclaimedFees[1]
        )
    ) {
      vm.expectRevert(BaseTickBasedRemoveLiquidityHook.NotEnoughFeesReceived.selector);
    } else if (actualReceived0 < minReceived0 || actualReceived1 < minReceived1) {
      vm.expectRevert(BaseTickBasedRemoveLiquidityHook.NotEnoughOutputAmount.selector);
    }
    router.execute(intentData, daSignature, guardian, gdSignature, actionData);
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

  function _setUpMainAddress(IntentData memory intentData, bool withSignedIntent, uint256 tokenId)
    internal
  {
    vm.startPrank(mainAddress);
    if (!withSignedIntent) {
      router.delegate(intentData);
    }
    pm.approve(address(router), tokenId);
    vm.stopPrank();
  }

  function _getIntentData(Node[] memory nodes) internal view returns (IntentData memory intentData) {
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

    IntentCoreData memory coreData = IntentCoreData({
      mainAddress: mainAddress,
      delegatedAddress: delegatedAddress,
      actionContracts: _toArray(address(mockActionContract)),
      actionSelectors: _toArray(MockActionContract.removeUniswapV3.selector),
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

  function _getActionData(TokenData memory tokenData, uint256 _liquidity)
    internal
    view
    returns (ActionData memory actionData)
  {
    actionData = ActionData({
      tokenData: tokenData,
      actionSelectorId: 0,
      actionCalldata: abi.encode(
        pm,
        tokenId,
        tokenOwner,
        address(router),
        token0,
        token1,
        _liquidity,
        transferPercent,
        wrapOrUnwrap,
        weth,
        takeUnclaimedFees,
        amounts,
        fees
      ),
      hookActionData: abi.encode(
        0, fees[0], fees[1], _liquidity, wrapOrUnwrap, intentFeesPercent0 << 128 | intentFeesPercent1
      ),
      extraData: '',
      deadline: block.timestamp + 1 days,
      nonce: 0
    });
  }

  function _computePositionValues() internal returns (uint256 amount0, uint256 amount1) {
    KSRemoveLiquidityUniswapV3Hook.RemoveLiquidityParams storage removeLiqParams =
      uniswapV3.removeLiqParams;
    KSRemoveLiquidityUniswapV3Hook.OutputValidationParams storage outputParams =
      uniswapV3.outputParams;
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
      positionInfo.unclaimedFees[0] += Math.mulDiv(
        feeGrowthInside0 - positionInfo.feesGrowthInsideLast[0], positionInfo.liquidity, Q128
      );
      positionInfo.unclaimedFees[1] += Math.mulDiv(
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

  function _overrideParams() internal {
    tokenId = 963_350; // out range position
    address posOwner = IUniswapV3PM(pm).ownerOf(tokenId);
    vm.prank(posOwner);
    IERC721(pm).safeTransferFrom(posOwner, mainAddress, tokenId);

    (
      ,
      ,
      address _token0,
      address _token1,
      ,
      int24 _tickLower,
      int24 _tickUpper,
      uint128 _liquidity,
      ,
      ,
      ,
    ) = pm.positions(tokenId);

    assertTrue(_tickLower > currentTick || _tickUpper < currentTick);
    assertTrue(_liquidity > 0, '_liquidity > 0');
    assertTrue(_token0 == token0, '_token0 == token0');
    assertTrue(_token1 == token1, '_token1 == token1');

    tickLower = _tickLower;
    tickUpper = _tickUpper;
    liquidity = _liquidity;

    (
      ,
      ,
      uniswapV3.outputParams.tokens[0],
      uniswapV3.outputParams.tokens[1],
      ,
      uniswapV3.removeLiqParams.positionInfo.ticks[0],
      uniswapV3.removeLiqParams.positionInfo.ticks[1],
      ,
      uniswapV3.removeLiqParams.positionInfo.feesGrowthInsideLast[0],
      uniswapV3.removeLiqParams.positionInfo.feesGrowthInsideLast[1],
      uniswapV3.removeLiqParams.positionInfo.unclaimedFees[0],
      uniswapV3.removeLiqParams.positionInfo.unclaimedFees[1]
    ) = IUniswapV3PM(pm).positions(tokenId);
    uniswapV3.removeLiqParams.positionInfo.liquidity = liquidity;
    uniswapV3.removeLiqParams.currentTick = currentTick;
    uniswapV3.removeLiqParams.sqrtPriceX96 = currentPrice;

    uniswapV3.removeLiqParams.liquidityToRemove = liquidity;
  }

  function _boundStruct(FuzzStruct memory fuzzStruct) internal {
    fuzzStruct.seed = bound(fuzzStruct.seed, 0, type(uint128).max);
    fuzzStruct.liquidityToRemove = bound(fuzzStruct.liquidityToRemove, 0, liquidity);
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
