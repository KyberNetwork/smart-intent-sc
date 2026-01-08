// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';

import 'src/types/ConditionTree.sol';
import 'test/mocks/MockConditionalHook.sol';

contract ConditionTreeTest is Test {
  OperationType constant AND = OperationType.AND;
  OperationType constant OR = OperationType.OR;
  ConditionType constant TIME_BASED = ConditionType.wrap(keccak256('TIME_BASED'));
  ConditionType constant PRICE_BASED = ConditionType.wrap(keccak256('PRICE_BASED'));

  bytes internal _mockPriceData = abi.encode(1000);
  Node[] internal _nodes;
  mapping(uint256 => bool) internal _isLeaf;
  MockConditionalHook internal _hook = new MockConditionalHook();

  function setUp() public {
    vm.warp(1_000_000_000);
  }

  function testFuzz_EvaluateTree(uint256 seed) public {
    seed = bound(seed, 1, type(uint128).max);
    uint256 maxDepth = bound(seed, 1, 10);
    uint256 maxChildren = bound(seed, 1, 10);
    uint256 curIndex = 0;

    (Node memory curNode, bool isLeaf,) = _buildRandomNode(seed, false);
    _nodes.push(curNode);
    _isLeaf[0] = isLeaf;

    for (uint256 i = 0; i < maxDepth; i++) {
      uint256 childrenLength = bound(seed, 1, maxChildren);
      curNode = _nodes[curIndex];

      if (_isLeaf[curIndex]) {
        // leaf node
        continue;
      }

      for (uint256 j = 1; j <= childrenLength; j++) {
        (Node memory childNode, bool childIsLeaf,) =
          _buildRandomNode(uint128(seed) + i + j, i == maxDepth - 1);

        uint256 childIndex = _nodes.length;
        _nodes.push(childNode);
        _isLeaf[childIndex] = childIsLeaf;
        _nodes[curIndex].childrenIndexes.push(childIndex);
      }
      curIndex++;
    }

    ConditionTree memory tree = _buildTree(_nodes);

    bool pass = this.callLibrary(tree, 0);
    if (!pass) {
      vm.expectRevert(IKSConditionalHook.ConditionsNotMet.selector);
    }
    _hook.validateConditionTree(tree, 0);
  }

  function testEvaluateNode_LeafNode_TrueCondition() public view {
    Condition memory condition = _createTimeCondition(true);

    Node[] memory nodes = new Node[](1);
    nodes[0] = _createLeafNode(condition);

    _hook.validateConditionTree(_buildTree(nodes), 0);
  }

  function testRevert_LeafNode_FalseCondition() public {
    // Create a leaf node with a time condition that should be false
    Condition memory condition = _createTimeCondition(false);

    Node[] memory nodes = new Node[](1);
    nodes[0] = _createLeafNode(condition);

    ConditionTree memory tree = _buildTree(nodes);

    vm.expectRevert(IKSConditionalHook.ConditionsNotMet.selector);
    _hook.validateConditionTree(tree, 0);
  }

  function testEvaluateNode_AndNode_AllChildrenTrue() public view {
    //  Create AND node with two leaf children that are both true
    Condition memory trueCondition1 = _createTimeCondition(true);
    Condition memory trueCondition2 = _createPriceCondition(true);

    Node[] memory nodes = new Node[](3);
    nodes[0] = _createLeafNode(trueCondition1); // index 0
    nodes[1] = _createLeafNode(trueCondition2); // index 1

    uint256[] memory children = new uint256[](2);
    children[0] = 0;
    children[1] = 1;
    nodes[2] = _createNode(children, AND); // (root)

    _hook.validateConditionTree(_buildTree(nodes), 2);
  }

  function testRevert_AndNode_OneChildFalse() public {
    //  Create AND node with one true and one false child
    Condition memory trueCondition = _createTimeCondition(true);
    Condition memory falseCondition = _createPriceCondition(false);

    Node[] memory nodes = new Node[](3);
    nodes[0] = _createLeafNode(trueCondition); // index 0 - true
    nodes[1] = _createLeafNode(falseCondition); // index 1 - false

    uint256[] memory children = new uint256[](2);
    children[0] = 0;
    children[1] = 1;
    nodes[2] = _createNode(children, AND); // index 2

    ConditionTree memory tree = _buildTree(nodes);
    vm.expectRevert(IKSConditionalHook.ConditionsNotMet.selector);
    _hook.validateConditionTree(tree, 2);
  }

  function testRevert_OrNode_AllChildrenFalse() public {
    //  Create OR node with two false children
    Condition memory falseCondition1 = _createTimeCondition(false);
    Condition memory falseCondition2 = _createPriceCondition(false);

    Node[] memory nodes = new Node[](3);
    nodes[0] = _createLeafNode(falseCondition1); // index 0 - false
    nodes[1] = _createLeafNode(falseCondition2); // index 1 - false

    uint256[] memory children = new uint256[](2);
    children[0] = 0;
    children[1] = 1;
    nodes[2] = _createNode(children, OR); // index 2 (root)

    ConditionTree memory tree = _buildTree(nodes);

    vm.expectRevert(IKSConditionalHook.ConditionsNotMet.selector);
    _hook.validateConditionTree(tree, 2);
  }

  function testEvaluateNode_OrNode_OneChildTrue() public view {
    //  Create OR node with one true and one false child
    Condition memory trueCondition = _createTimeCondition(true);
    Condition memory falseCondition = _createPriceCondition(false);

    Node[] memory nodes = new Node[](3);
    nodes[0] = _createLeafNode(trueCondition); // index 0 - true
    nodes[1] = _createLeafNode(falseCondition); // index 1 - false

    uint256[] memory children = new uint256[](2);
    children[0] = 0;
    children[1] = 1;
    nodes[2] = _createNode(children, OR); // index 2

    _hook.validateConditionTree(_buildTree(nodes), 2);
  }

  function testEvaluateNode_NestedNodes() public view {
    // Tree structure:
    //          OR (index 6)
    //         /            \
    //    AND (4)          AND (5)
    //    /     \          /     \
    //   A(0)   B(1)     C(2)   D(3)
    //  true   false     true   true
    //
    // Expected result: (true AND false) OR (true AND true) = false OR true = true

    // Create leaf conditions
    Condition memory conditionA = _createTimeCondition(true);
    Condition memory conditionB = _createTimeCondition(false);
    Condition memory conditionC = _createPriceCondition(true);
    Condition memory conditionD = _createPriceCondition(true);

    Node[] memory nodes = new Node[](7);
    nodes[0] = _createLeafNode(conditionA); // A (true)
    nodes[1] = _createLeafNode(conditionB); // B (false)
    nodes[2] = _createLeafNode(conditionC); // C (true)
    nodes[3] = _createLeafNode(conditionD); // D (true)

    // Create AND nodes
    uint256[] memory andChildren1 = new uint256[](2);
    andChildren1[0] = 0; // A
    andChildren1[1] = 1; // B
    nodes[4] = _createNode(andChildren1, AND); // A AND B (false)

    uint256[] memory andChildren2 = new uint256[](2);
    andChildren2[0] = 2; // C
    andChildren2[1] = 3; // D
    nodes[5] = _createNode(andChildren2, AND); // C AND D (true)

    // Create root OR node
    uint256[] memory orChildren = new uint256[](2);
    orChildren[0] = 4; // A AND B
    orChildren[1] = 5; // C AND D
    nodes[6] = _createNode(orChildren, OR); // (A AND B) OR (C AND D)

    _hook.validateConditionTree(_buildTree(nodes), 6);
  }

  function testRevert_InvalidNodeIndex() public {
    //  Create a single node but try to access index 1
    Node[] memory nodes = new Node[](1);
    nodes[0] = _createLeafNode(_createTimeCondition(true));

    ConditionTree memory tree = _buildTree(nodes);

    vm.expectRevert(ConditionTreeLibrary.InvalidNodeIndex.selector);
    _hook.validateConditionTree(tree, 1);
  }

  function testEvaluateNode_SingleNode() public view {
    Condition memory condition = _createPriceCondition(true);

    Node[] memory nodes = new Node[](1);
    uint256[] memory emptyChildren = new uint256[](0);
    nodes[0] = Node({
      operationType: OperationType.AND, condition: condition, childrenIndexes: emptyChildren
    });

    _hook.validateConditionTree(_buildTree(nodes), 0);
  }

  function testEvaluateNode_SingleChildAnd() public view {
    Condition memory trueCondition = _createPriceCondition(true);

    Node[] memory nodes = new Node[](2);
    nodes[0] = _createLeafNode(trueCondition); // index 0

    uint256[] memory children = new uint256[](1);
    children[0] = 0;
    nodes[1] = _createNode(children, AND); // index 1

    _hook.validateConditionTree(_buildTree(nodes), 1);
  }

  function testRevert_SingleChildOr() public {
    Condition memory falseCondition = _createPriceCondition(false);

    Node[] memory nodes = new Node[](2);
    nodes[0] = _createLeafNode(falseCondition); // index 0

    uint256[] memory children = new uint256[](1);
    children[0] = 0;
    nodes[1] = _createNode(children, OR); // index 1

    ConditionTree memory tree = _buildTree(nodes);
    vm.expectRevert(IKSConditionalHook.ConditionsNotMet.selector);
    _hook.validateConditionTree(tree, 1);
  }

  function testEvaluateNode_MultipleAndLevels() public view {
    // Tree structure:
    //         AND (index 6)
    //        /            \
    //      A(0)          AND (5)
    //      true         /       \
    //                 B(1)     AND (4)
    //                 true    /       \
    //                       C(2)     D(3)
    //                       true     true
    //
    // Expected result: true AND (true AND (true AND true)) = true AND (true AND true) = true AND true = true

    Node[] memory nodes = new Node[](7);

    // Leaf nodes - all true
    nodes[0] = _createLeafNode(_createPriceCondition(true)); // A
    nodes[1] = _createLeafNode(_createPriceCondition(true)); // B
    nodes[2] = _createLeafNode(_createTimeCondition(true)); // C
    nodes[3] = _createLeafNode(_createTimeCondition(true)); // D

    // Build from innermost: C AND D
    uint256[] memory innerChildren = new uint256[](2);
    innerChildren[0] = 2; // C
    innerChildren[1] = 3; // D
    nodes[4] = _createNode(innerChildren, AND);

    // B AND (C AND D)
    uint256[] memory middleChildren = new uint256[](2);
    middleChildren[0] = 1; // B
    middleChildren[1] = 4; // C AND D
    nodes[5] = _createNode(middleChildren, AND);

    // A AND (B AND (C AND D))
    uint256[] memory outerChildren = new uint256[](2);
    outerChildren[0] = 0; // A
    outerChildren[1] = 5; // B AND (C AND D)
    nodes[6] = _createNode(outerChildren, AND); // root

    _hook.validateConditionTree(_buildTree(nodes), 6);
  }

  function _createRandomCondition(uint256 seed, bool isTrue)
    internal
    view
    returns (Condition memory)
  {
    seed = bound((seed * 2) << 2, 0, 1);
    if (seed == 0) {
      return _createTimeCondition(isTrue);
    } else {
      return _createPriceCondition(isTrue);
    }
  }

  function _buildRandomNode(uint256 seed, bool mustBeLeaf)
    internal
    view
    returns (Node memory, bool isLeaf, bool conditionPass)
  {
    isLeaf = bound(seed, 0, 1) == 1;
    conditionPass = bound(seed * 2 + 1, 0, 1) == 1;
    if (mustBeLeaf || isLeaf) {
      Condition memory condition = _createRandomCondition(seed, conditionPass);
      return (_createLeafNode(condition), true, conditionPass);
    } else {
      OperationType opType = (seed << 1) % 3 == 0 ? AND : OR;
      return (_createNode(new uint256[](0), opType), false, false);
    }
  }

  function _createTimeCondition(bool isTrue) internal view returns (Condition memory) {
    TimeCondition memory timeCondition = TimeCondition({
      startTimestamp: isTrue ? block.timestamp - 100 : block.timestamp + 100,
      endTimestamp: isTrue ? block.timestamp + 100 : block.timestamp + 200
    });

    return Condition({conditionType: TIME_BASED, data: abi.encode(timeCondition)});
  }

  function _createPriceCondition(bool isTrue) internal pure returns (Condition memory) {
    PriceCondition memory priceCondition =
      PriceCondition({minPrice: isTrue ? 0 : type(uint256).max, maxPrice: type(uint256).max});

    return Condition({conditionType: PRICE_BASED, data: abi.encode(priceCondition)});
  }

  // Test helper to create a leaf node
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

  function _buildTree(Node[] memory nodes) internal view returns (ConditionTree memory) {
    return ConditionTree({nodes: nodes, additionalData: this.createMockData(nodes)});
  }

  function callLibrary(ConditionTree calldata tree, uint256 curIndex) external view returns (bool) {
    return ConditionTreeLibrary.evaluateConditionTree(tree, curIndex, evaluateCondition);
  }

  function evaluateCondition(Condition calldata condition, bytes calldata additionalData)
    public
    view
    returns (bool)
  {
    return _hook.evaluateCondition(condition, additionalData);
  }

  function createMockData(Node[] calldata nodes) external view returns (bytes[] memory) {
    bytes[] memory additionalData = new bytes[](nodes.length);
    Condition calldata condition;
    for (uint256 i = 0; i < nodes.length; i++) {
      if (!nodes[i].isLeaf()) {
        continue;
      }

      condition = nodes[i].condition;
      if (condition.isType(TIME_BASED)) {
        additionalData[i] = '';
      } else if (condition.isType(PRICE_BASED)) {
        additionalData[i] = _mockPriceData;
      }
    }
    return additionalData;
  }
}
