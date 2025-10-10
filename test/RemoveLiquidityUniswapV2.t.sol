// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.t.sol';
import 'src/hooks/remove-liq/KSRemoveLiquidityUniswapV2Hook.sol';

import {IUniswapV2Pair} from 'src/interfaces/uniswapv2/IUniswapV2Pair.sol';
import {IUniswapV2Router} from 'src/interfaces/uniswapv2/IUniswapV2Router.sol';

import './libraries/ArraysHelper.sol';
import {PackedU128} from 'src/libraries/types/PackedU128.sol';
import 'test/common/Permit.sol';

contract RemoveLiquidityUniswapV2Test is BaseTest {
  using ArraysHelper for *;

  using SafeERC20 for IERC20;
  using TokenHelper for address;

  IUniswapV2Router uniRouter = IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
  IUniswapV2Pair pair = IUniswapV2Pair(0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852);
  address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  uint256 maxFeePercents = 20_000; // 2%
  uint256 intentFeesPercent0 = 10_000; // 1%
  uint256 intentFeesPercent1 = 10_000; // 1%
  uint256 fee0Generated = 0.001 ether;
  uint256 fee1Generated = 0.001 ether;
  uint256 amount0;
  uint256 amount1;
  address token0;
  address token1;
  ConditionType constant TIME_BASED = ConditionType.wrap(keccak256('TIME_BASED'));
  ConditionType constant PRICE_BASED = ConditionType.wrap(keccak256('PRICE_BASED'));
  ConditionType constant YIELD_BASED = ConditionType.wrap(keccak256('YIELD_BASED'));
  OperationType constant AND = OperationType.AND;
  OperationType constant OR = OperationType.OR;
  Node[] internal _nodes;
  mapping(uint256 => bool) internal _isLeaf;
  KSRemoveLiquidityUniswapV2Hook rmLqValidator;

  function setUp() public override {
    super.setUp();

    token0 = pair.token0();
    token1 = pair.token1();
    deal(token0, mainAddress, 10 ether);
    deal(token1, mainAddress, 100_000e6);
    vm.startPrank(mainAddress);
    token0.safeApprove(address(uniRouter), type(uint128).max);
    token1.safeApprove(address(uniRouter), type(uint128).max);
    uniRouter.addLiquidity(
      token0, token1, 10 ether, 100_000e6, 0, 0, mainAddress, block.timestamp + 1 days
    );
    vm.stopPrank();

    rmLqValidator = new KSRemoveLiquidityUniswapV2Hook();

    vm.prank(admin);
    router.grantRole(ACTION_CONTRACT_ROLE, address(uniRouter));
  }

  struct FuzzStruct {
    uint256 seed;
    uint256 liquidityToRemove;
    bool withSignedIntent;
    ConditionType conditionType;
    bool conditionPass;
    uint256 maxFeePercents;
  }

  function _selectFork() public override {
    FORK_BLOCK = 22_230_873;
    vm.createSelectFork('mainnet', FORK_BLOCK);
  }

  function testFuzz_RemoveLiquidityUniswapV2(FuzzStruct memory fuzz) public {
    _boundStruct(fuzz);
    _computePositionValues(fuzz.liquidityToRemove);

    Node[] memory nodes = _randomNodes(fuzz);
    ConditionTree memory conditionTree = this.buildConditionTree(
      nodes,
      fee0Generated,
      fee1Generated,
      token0.balanceOf(address(pair)) * 1e18 / token1.balanceOf(address(pair))
    );
    bool conditionPass = this.callLibrary(conditionTree, 0);
    IntentData memory intentData = _getIntentData(nodes);

    _setUpMainAddress(intentData, false);

    ActionData memory actionData = _getActionData(fuzz.liquidityToRemove);

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
      uint256 intentFee0 = amount0 * intentFeesPercent0 / 1_000_000;
      uint256 intentFee1 = amount1 * intentFeesPercent1 / 1_000_000;
      assertEq(balance0After - balance0Before, amount0 - intentFee0, 'invalid token0 received');
      assertEq(balance1After - balance1Before, amount1 - intentFee1, 'invalid token1 received');
      assertEq(token0.balanceOf(feeRecipient), intentFee0, 'invalid fee0 received');
      assertEq(token1.balanceOf(feeRecipient), intentFee1, 'invalid fee1 received');
    }
  }

  function testRevert_InvalidFees(FuzzStruct memory fuzz) public {
    _boundStruct(fuzz);
    fuzz.conditionPass = true;
    _computePositionValues(fuzz.liquidityToRemove);
    intentFeesPercent0 = 100_000;
    intentFeesPercent1 = 100_000;

    Node[] memory nodes = _randomNodes(fuzz);
    ConditionTree memory conditionTree = this.buildConditionTree(
      nodes,
      fee0Generated,
      fee1Generated,
      token0.balanceOf(address(pair)) * 1e18 / token1.balanceOf(address(pair))
    );
    bool conditionPass = this.callLibrary(conditionTree, 0);
    IntentData memory intentData = _getIntentData(nodes);

    _setUpMainAddress(intentData, false);

    ActionData memory actionData = _getActionData(fuzz.liquidityToRemove);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    vm.startPrank(caller);
    vm.expectRevert(abi.encodeWithSelector(KSRemoveLiquidityUniswapV2Hook.InvalidFees.selector));
    router.execute(intentData, daSignature, guardian, gdSignature, actionData);
  }

  function testRevert_InvalidLpValues() public {
    Node[] memory nodes = new Node[](1);
    nodes[0] = _createLeafNode(_createYieldCondition(true));
    ConditionTree memory conditionTree = this.buildConditionTree(
      nodes,
      fee0Generated,
      fee1Generated,
      token0.balanceOf(address(pair)) * 1e18 / token1.balanceOf(address(pair))
    );
    bool conditionPass = this.callLibrary(conditionTree, 0);
    IntentData memory intentData = _getIntentData(nodes);

    _setUpMainAddress(intentData, false);

    ActionData memory actionData = _getActionData(100_000);

    actionData.actionCalldata =
      abi.encode(token0, token1, 90_000, 0, 0, address(router), block.timestamp + 1 days);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    vm.startPrank(caller);
    vm.expectRevert(abi.encodeWithSelector(KSRemoveLiquidityUniswapV2Hook.InvalidLpValues.selector));
    router.execute(intentData, daSignature, guardian, gdSignature, actionData);
  }

  function buildConditionTree(
    Node[] calldata nodes,
    uint256 fee0Collected,
    uint256 fee1Collected,
    uint256 price
  ) external pure returns (ConditionTree memory conditionTree) {
    conditionTree.nodes = nodes;
    conditionTree.additionalData = new bytes[](nodes.length);
    for (uint256 i; i < nodes.length; ++i) {
      if (!nodes[i].isLeaf() || nodes[i].condition.isType(TIME_BASED)) {
        continue;
      }
      if (nodes[i].condition.isType(YIELD_BASED)) {
        conditionTree.additionalData[i] = abi.encode(fee0Collected, fee1Collected, price);
      } else if (nodes[i].condition.isType(PRICE_BASED)) {
        conditionTree.additionalData[i] = abi.encode(price);
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

  function _computePositionValues(uint256 liquidity) internal {
    uint256 totalSupply = IUniswapV2Pair(pair).totalSupply();
    uint256 balance0 = token0.balanceOf(address(pair));
    uint256 balance1 = token1.balanceOf(address(pair));

    console.log('totalSupply', totalSupply);
    console.log('liquidity', liquidity);
    console.log('balance0', balance0);
    console.log('balance1', balance1);

    amount0 = liquidity * balance0 / totalSupply;
    amount1 = liquidity * balance1 / totalSupply;
    console.log('amount0', amount0);
    console.log('amount1', amount1);
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
    } else if (ConditionType.unwrap(fuzzStruct.conditionType) == ConditionType.unwrap(TIME_BASED)) {
      return _createTimeCondition(fuzzStruct.conditionPass);
    } else {
      revert('WrongConditionType');
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

  function _setUpMainAddress(IntentData memory intentData, bool withSignedIntent) internal {
    vm.startPrank(mainAddress);
    if (!withSignedIntent) {
      router.delegate(intentData);
    }
    address(pair).safeApprove(address(router), type(uint128).max);
    vm.stopPrank();
  }

  function _getIntentData(Node[] memory nodes) internal view returns (IntentData memory intentData) {
    KSRemoveLiquidityUniswapV2Hook.UniswapV2Params memory hookData;
    hookData.pairs = [address(pair)].toMemoryArray();
    hookData.maxFees = new PackedU128[](1);
    hookData.maxFees[0] = toPackedU128(maxFeePercents, maxFeePercents);
    hookData.recipient = mainAddress;

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

    address[] memory actionContracts = new address[](1);
    actionContracts[0] = address(uniRouter);

    bytes4[] memory actionSelectors = new bytes4[](1);
    actionSelectors[0] = IUniswapV2Router.removeLiquidity.selector;

    IntentCoreData memory coreData = IntentCoreData({
      mainAddress: mainAddress,
      delegatedAddress: delegatedAddress,
      actionContracts: actionContracts,
      actionSelectors: actionSelectors,
      hook: address(rmLqValidator),
      hookIntentData: abi.encode(hookData)
    });

    TokenData memory tokenData;
    tokenData.erc20Data = new ERC20Data[](2);
    tokenData.erc20Data[0] =
      ERC20Data({token: address(pair), amount: type(uint128).max, permitData: ''});

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
          initialAmounts: (1 ether << 128) | 1 ether
        })
      );
    } else {
      condition.data = abi.encode(
        YieldCondition({
          targetYield: 10_000_000, // 1000%
          initialAmounts: (1 ether << 128) | 1 ether
        })
      );
    }
  }

  function _createTimeCondition(bool isTrue) internal view returns (Condition memory) {
    console.log('block.timestamp', block.timestamp);
    console.log('timeCondition');
    TimeCondition memory timeCondition = TimeCondition({
      startTimestamp: isTrue ? block.timestamp - 100 : block.timestamp + 100,
      endTimestamp: isTrue ? block.timestamp + 100 : block.timestamp + 200
    });

    return Condition({conditionType: TIME_BASED, data: abi.encode(timeCondition)});
  }

  function _createPriceCondition(bool isTrue) internal view returns (Condition memory) {
    PriceCondition memory priceCondition;
    uint256 currentPrice = token0.balanceOf(address(pair)) * 1e18 / token1.balanceOf(address(pair));
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
    actionData = ActionData({
      erc20Ids: [uint256(0)].toMemoryArray(),
      erc20Amounts: [_liquidity].toMemoryArray(),
      erc721Ids: new uint256[](0),
      actionSelectorId: 0,
      approvalFlags: type(uint256).max,
      actionCalldata: abi.encode(
        token0, token1, _liquidity, 0, 0, address(router), block.timestamp + 1 days
      ),
      hookActionData: abi.encode(
        0,
        toPackedU128(fee0Generated, fee1Generated),
        toPackedU128(intentFeesPercent0, intentFeesPercent1)
      ),
      extraData: '',
      deadline: block.timestamp + 1 days,
      nonce: 0
    });
  }

  function _boundStruct(FuzzStruct memory fuzzStruct) internal {
    fuzzStruct.seed = bound(fuzzStruct.seed, 0, type(uint128).max);
    fuzzStruct.liquidityToRemove =
      bound(fuzzStruct.liquidityToRemove, 100_000, address(pair).balanceOf(mainAddress));
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
