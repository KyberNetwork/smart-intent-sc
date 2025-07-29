// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.t.sol';

import 'ks-common-sc/libraries/token/TokenHelper.sol';
import 'src/validators/remove-liq-validators/KSRemoveLiquidityUniswapV4IntentValidator.sol';
import 'test/common/Permit.sol';

contract RemoveLiquidityUniV4Test is BaseTest {
  using SafeERC20 for IERC20;
  using TokenHelper for address;
  using StateLibrary for IPoolManager;

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
  ConditionType constant TIME_BASED = ConditionType.wrap(keccak256('TIME_BASED'));
  ConditionType constant PRICE_BASED = ConditionType.wrap(keccak256('PRICE_BASED'));
  ConditionType constant UNIV4_YIELD_BASED = ConditionType.wrap(keccak256('UNIV4_YIELD_BASED'));
  OperationType constant AND = OperationType.AND;
  OperationType constant OR = OperationType.OR;
  uint256 magicNumber = 1e6;
  uint256 maxFeePercents = 20_000; // 2%
  Node[] internal _nodes;
  mapping(uint256 => bool) internal _isLeaf;
  uint256 constant PRECISION = 1_000_000;
  address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  bool wrapOrUnwrap;

  KSRemoveLiquidityUniswapV4IntentValidator rmLqValidator;

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

    rmLqValidator = new KSRemoveLiquidityUniswapV4IntentValidator(weth);
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
    wrapOrUnwrap = bound(fuzzStruct.seed, 0, 1) == 1;

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

    Node[] memory nodes = _randomNodes(fuzzStruct);
    ConditionTree memory conditionTree = this.buildConditionTree(nodes, fee0, fee1, currentPrice);
    bool pass = this.callLibrary(conditionTree, 0);

    IKSSessionIntentRouter.IntentData memory intentData =
      _getIntentData(fuzzStruct.usePermit, nodes);

    _setUpMainAddress(intentData, fuzzStruct.withSignedIntent, uniV4TokenId, !fuzzStruct.usePermit);

    IKSSessionIntentRouter.ActionData memory actionData =
      _getActionData(intentData.tokenData, fuzzStruct.liquidityToRemove);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    bytes memory maSignature = _getMASignature(intentData);

    if (wrapOrUnwrap) {
      token0 = weth;
    }

    uint256 balance0Before = token0.balanceOf(mainAddress);
    uint256 balance1Before = token1.balanceOf(mainAddress);

    bool isRevert;
    vm.startPrank(caller);
    if (fuzzStruct.withSignedIntent) {
      if (!pass || maxFeePercents > PRECISION) {
        isRevert = true;
        if (!pass) {
          vm.expectRevert(IKSConditionalValidator.ConditionsNotMet.selector);
        } else if (maxFeePercents > PRECISION) {
          vm.expectRevert(KSRemoveLiquidityUniswapV4IntentValidator.InvalidOutputAmount.selector);
        }
      }
      router.executeWithSignedIntent(
        intentData, maSignature, daSignature, guardian, gdSignature, actionData
      );
    } else {
      bytes32 hash = router.hashTypedIntentData(intentData);
      if (!pass || fuzzStruct.maxFeePercents > PRECISION) {
        isRevert = true;
        if (!pass) {
          vm.expectRevert(IKSConditionalValidator.ConditionsNotMet.selector);
        } else if (fuzzStruct.maxFeePercents > PRECISION) {
          vm.expectRevert(KSRemoveLiquidityUniswapV4IntentValidator.InvalidOutputAmount.selector);
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
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(withPermit, new Node[](0));

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

    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(withPermit, nodes);

    _setUpMainAddress(intentData, false, uniV4TokenId, !withPermit);

    IKSSessionIntentRouter.ActionData memory actionData =
      _getActionData(intentData.tokenData, liquidity);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    vm.warp(block.timestamp + 100);
    bytes32 intentDataHash = router.hashTypedIntentData(intentData);
    vm.startPrank(caller);
    vm.expectRevert(IKSConditionalValidator.ConditionsNotMet.selector);
    router.execute(intentDataHash, daSignature, guardian, gdSignature, actionData);
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

    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(withPermit, nodes);

    _setUpMainAddress(intentData, false, uniV4TokenId, !withPermit);

    IKSSessionIntentRouter.ActionData memory actionData =
      _getActionData(intentData.tokenData, liquidity);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    bytes32 intentDataHash = router.hashTypedIntentData(intentData);
    vm.startPrank(caller);
    vm.expectRevert(IKSConditionalValidator.ConditionsNotMet.selector);
    router.execute(intentDataHash, daSignature, guardian, gdSignature, actionData);
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

    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(withPermit, nodes);

    _setUpMainAddress(intentData, false, uniV4TokenId, !withPermit);

    IKSSessionIntentRouter.ActionData memory actionData =
      _getActionData(intentData.tokenData, liquidity);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    bytes32 intentDataHash = router.hashTypedIntentData(intentData);
    vm.startPrank(caller);
    vm.expectRevert(IKSConditionalValidator.ConditionsNotMet.selector);
    router.execute(intentDataHash, daSignature, guardian, gdSignature, actionData);
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

    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(withPermit, nodes);

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
    Node[] memory nodes = new Node[](3);
    nodes[1] = _createLeafNode(_createYieldCondition(false));
    nodes[2] = _createLeafNode(_createTimeCondition(true));
    uint256[] memory andChildren = new uint256[](2);
    andChildren[0] = 1;
    andChildren[1] = 2;
    nodes[0] = _createNode(andChildren, OR);

    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(withPermit, nodes);

    _setUpMainAddress(intentData, false, uniV4TokenId, !withPermit);

    IKSSessionIntentRouter.ActionData memory actionData =
      _getActionData(intentData.tokenData, liquidity);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    bytes32 intentDataHash = router.hashTypedIntentData(intentData);
    vm.startPrank(caller);
    router.execute(intentDataHash, daSignature, guardian, gdSignature, actionData);
  }

  function test_executeSignedIntent_RemoveSuccess() public {
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(true, new Node[](0));
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
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(true, new Node[](0));
    _setUpMainAddress(intentData, false, uniV4TokenId, false);

    magicNumber = MAGIC_NUMBER_NOT_TRANSFER;

    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(intentData.tokenData, liq);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    bytes32 intentDataHash = router.hashTypedIntentData(intentData);
    vm.startPrank(caller);
    vm.expectRevert(KSRemoveLiquidityUniswapV4IntentValidator.InvalidOutputAmount.selector);
    router.execute(intentDataHash, daSignature, guardian, gdSignature, actionData);
  }

  function testRevert_validationAfterExecution_InvalidOwner(uint256 liq) public {
    liq = bound(liq, 0, liquidity);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(true, new Node[](0));
    _setUpMainAddress(intentData, false, uniV4TokenId, false);

    nftOwner = address(0);

    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(intentData.tokenData, liq);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    bytes32 intentDataHash = router.hashTypedIntentData(intentData);
    vm.startPrank(caller);
    vm.expectRevert(KSRemoveLiquidityUniswapV4IntentValidator.InvalidOwner.selector);
    router.execute(intentDataHash, daSignature, guardian, gdSignature, actionData);
  }

  function test_RemoveSuccess_Transfer99Percent(uint256 liq) public {
    liq = bound(liq, 0, liquidity);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(true, new Node[](0));
    _setUpMainAddress(intentData, false, uniV4TokenId, false);

    magicNumber = 990_000;

    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(intentData.tokenData, liq);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    bytes32 intentDataHash = router.hashTypedIntentData(intentData);
    vm.startPrank(caller);
    router.execute(intentDataHash, daSignature, guardian, gdSignature, actionData);
  }

  function testRevert_Transfer97Percent(uint256 liq) public {
    liq = bound(liq, 0, liquidity);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(true, new Node[](0));
    _setUpMainAddress(intentData, false, uniV4TokenId, false);

    magicNumber = 970_000;

    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(intentData.tokenData, liq);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    bytes32 intentDataHash = router.hashTypedIntentData(intentData);
    vm.startPrank(caller);
    vm.expectRevert(KSRemoveLiquidityUniswapV4IntentValidator.InvalidOutputAmount.selector);
    router.execute(intentDataHash, daSignature, guardian, gdSignature, actionData);
  }

  function testFuzz_OutputAmounts(uint256 liq, uint256 transferPercent) public {
    wrapOrUnwrap = bound(liq, 0, 1) == 1;
    liq = bound(liq, 0, liquidity);
    transferPercent = bound(transferPercent, 0, 1_000_000);
    magicNumber = transferPercent;
    maxFeePercents = bound(maxFeePercents, 1, 1e6);

    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(true, new Node[](0));
    _setUpMainAddress(intentData, false, uniV4TokenId, false);

    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(intentData.tokenData, liq);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);
    bytes32 intentDataHash = router.hashTypedIntentData(intentData);

    vm.startPrank(caller);
    if (1e6 - transferPercent > maxFeePercents) {
      vm.expectRevert(KSRemoveLiquidityUniswapV4IntentValidator.InvalidOutputAmount.selector);
    }
    router.execute(intentDataHash, daSignature, guardian, gdSignature, actionData);
  }

  function _getIntentData(bool withPermit, Node[] memory nodes)
    internal
    view
    returns (IKSSessionIntentRouter.IntentData memory intentData)
  {
    KSRemoveLiquidityUniswapV4IntentValidator.RemoveLiquidityValidationData memory validationData;
    validationData.nftAddresses = new address[](1);
    validationData.nftAddresses[0] = pm;
    validationData.nftIds = new uint256[](1);
    validationData.nftIds[0] = uniV4TokenId;
    validationData.maxFees = new uint256[][](1);
    validationData.maxFees[0] = new uint256[](2);
    validationData.maxFees[0][0] = maxFeePercents;
    validationData.maxFees[0][1] = maxFeePercents;
    validationData.wrapOrUnwrap = new bool[](1);
    validationData.wrapOrUnwrap[0] = wrapOrUnwrap;

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

  function _getActionData(IKSSessionIntentRouter.TokenData memory tokenData, uint256 liquidity)
    internal
    view
    returns (IKSSessionIntentRouter.ActionData memory actionData)
  {
    actionData = IKSSessionIntentRouter.ActionData({
      tokenData: tokenData,
      actionSelectorId: 0,
      actionCalldata: abi.encode(
        pm, uniV4TokenId, nftOwner, token0, token1, liquidity, magicNumber, wrapOrUnwrap, weth
      ),
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
    fuzzStruct.seed = bound(fuzzStruct.seed, 0, type(uint128).max);
    fuzzStruct.liquidityToRemove = bound(fuzzStruct.liquidityToRemove, 0, liquidity);
    maxFeePercents = bound(maxFeePercents, 0, type(uint128).max);
    fuzzStruct.maxFeePercents = maxFeePercents;

    (uint256 received0, uint256 received1, uint256 unclaimedFee0, uint256 unclaimedFee1) =
    IPositionManager(pm).poolManager().computePositionValues(
      IPositionManager(pm), uniV4TokenId, liquidity
    );

    amount0 = received0;
    amount1 = received1;

    uint256 typeUint = bound(uint256(ConditionType.unwrap(fuzzStruct.conditionType)), 0, 2);
    if (typeUint == 0) {
      fuzzStruct.conditionType = UNIV4_YIELD_BASED;
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
      if (nodes[i].condition.isType(UNIV4_YIELD_BASED)) {
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
      OperationType opType = curNode.operationType;

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
    returns (Node memory, bool isLeaf)
  {
    isLeaf = bound(fuzzStruct.seed, 0, 1) == 1;
    bool conditionPass = bound(fuzzStruct.seed * 2 + 1, 0, 1) == 1;
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
    if (ConditionType.unwrap(fuzzStruct.conditionType) == ConditionType.unwrap(UNIV4_YIELD_BASED)) {
      return _createYieldCondition(fuzzStruct.conditionPass);
    } else if (ConditionType.unwrap(fuzzStruct.conditionType) == ConditionType.unwrap(PRICE_BASED))
    {
      return _createPriceCondition(fuzzStruct.conditionPass);
    } else {
      return _createTimeCondition(fuzzStruct.conditionPass);
    }
  }

  function _createYieldCondition(bool isTrue) internal view returns (Condition memory condition) {
    condition.conditionType = UNIV4_YIELD_BASED;

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
