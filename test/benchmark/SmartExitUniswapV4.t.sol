// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../Base.t.sol';

import 'ks-common-sc/src/libraries/token/TokenHelper.sol';
import 'src/hooks/remove-liq/KSRemoveLiquidityUniswapV4Hook.sol';

import {Actions} from 'src/interfaces/pancakev4/Types.sol';
import 'test/common/Permit.sol';

contract SmartExitUniswapV4Benchmark is BaseTest {
  using SafeERC20 for IERC20;
  using TokenHelper for address;
  using StateLibrary for IPoolManager;
  using ArraysHelper for *;

  address pm = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
  address uniV4TokenOwner = 0x1f2F10D1C40777AE1Da742455c65828FF36Df387;
  address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  uint256 uniV4TokenId = 55_783;
  address token0 = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
  address token1 = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

  ConditionType constant TIME_BASED = ConditionType.wrap(keccak256('TIME_BASED'));
  ConditionType constant PRICE_BASED = ConditionType.wrap(keccak256('PRICE_BASED'));
  ConditionType constant YIELD_BASED = ConditionType.wrap(keccak256('YIELD_BASED'));
  OperationType constant AND = OperationType.AND;
  OperationType constant OR = OperationType.OR;

  KSRemoveLiquidityUniswapV4Hook rmLqHook;

  function setUp() public override {
    FORK_BLOCK = 23_283_836;
    super.setUp();

    rmLqHook = new KSRemoveLiquidityUniswapV4Hook(weth);

    (, uint256 positionIn) = IPositionManager(pm).getPoolAndPositionInfo(uniV4TokenId);
    IPoolManager poolManager = IPositionManager(pm).poolManager();
    address posOwner = IERC721(pm).ownerOf(uniV4TokenId);
    vm.prank(posOwner);
    IERC721(pm).safeTransferFrom(posOwner, mainAddress, uniV4TokenId);

    vm.prank(admin);
    router.grantRole(ACTION_CONTRACT_ROLE, address(pm));
  }

  function testDelegate_NoPermit_NoCondition() public {
    IntentData memory intentData = _getIntentData(false, new Node[](0));

    vm.startPrank(mainAddress);
    router.delegate(intentData);
    vm.stopPrank();

    vm.snapshotGasLastCall('test_delegate_no_permit_no_condition');
  }

  function testDelegate_OneCondition_YieldBased() public {
    Node[] memory nodes = new Node[](1);
    nodes[0] = _createLeafNode(_createCondition(YIELD_BASED));
    IntentData memory intentData = _getIntentData(false, nodes);

    vm.startPrank(mainAddress);
    router.delegate(intentData);
    vm.stopPrank();

    vm.snapshotGasLastCall('test_delegate_one_condition_yield_based');
  }

  function testDelegate_OneCondition_PriceBased() public {
    Node[] memory nodes = new Node[](1);
    nodes[0] = _createLeafNode(_createCondition(PRICE_BASED));
    IntentData memory intentData = _getIntentData(false, nodes);

    vm.startPrank(mainAddress);
    router.delegate(intentData);
    vm.stopPrank();

    vm.snapshotGasLastCall('test_delegate_one_condition_price_based');
  }

  function testDelegate_OneCondition_TimeBased() public {
    Node[] memory nodes = new Node[](1);
    nodes[0] = _createLeafNode(_createCondition(TIME_BASED));
    IntentData memory intentData = _getIntentData(false, nodes);

    vm.startPrank(mainAddress);
    router.delegate(intentData);
    vm.stopPrank();

    vm.snapshotGasLastCall('test_delegate_one_condition_time_based');
  }

  function testDelegate_WithPermit_NoCondition() public {
    IntentData memory intentData = _getIntentData(true, new Node[](0));

    vm.startPrank(mainAddress);
    router.delegate(intentData);
    vm.stopPrank();
    vm.snapshotGasLastCall('test_delegate_with_permit_no_condition');
  }

  function testDelegate_ThreeNodes() public {
    Node[] memory nodes = new Node[](3);
    nodes[1] = _createLeafNode(_createCondition(PRICE_BASED));
    nodes[2] = _createLeafNode(_createCondition(YIELD_BASED));

    uint256[] memory andChildren = new uint256[](2);
    andChildren[0] = 1;
    andChildren[1] = 2;
    nodes[0] = _createParentNode(andChildren, AND);

    IntentData memory intentData = _getIntentData(false, nodes);

    vm.startPrank(mainAddress);
    router.delegate(intentData);
    vm.stopPrank();
    vm.snapshotGasLastCall('test_delegate_three_nodes');
  }

  function testDelegate_FiveNodes() public {
    Node[] memory nodes = new Node[](5);
    nodes[1] = _createLeafNode(_createCondition(PRICE_BASED));
    nodes[2] = _createLeafNode(_createCondition(YIELD_BASED));
    nodes[3] = _createLeafNode(_createCondition(TIME_BASED));
    nodes[4] = _createLeafNode(_createCondition(YIELD_BASED));
    uint256[] memory andChildren = new uint256[](4);
    andChildren[0] = 1;
    andChildren[1] = 2;
    andChildren[2] = 3;
    andChildren[3] = 4;

    nodes[0] = _createParentNode(andChildren, AND);

    IntentData memory intentData = _getIntentData(false, nodes);

    vm.startPrank(mainAddress);
    router.delegate(intentData);
    vm.stopPrank();
    vm.snapshotGasLastCall('test_delegate_five_nodes');
  }

  function testExecute_OneNode_FeeOn_NativeAndERC20() public {
    Node[] memory nodes = new Node[](1);
    nodes[0] = _createLeafNode(_createCondition(TIME_BASED));
    IntentData memory intentData = _getIntentData(false, nodes);

    vm.startPrank(mainAddress);
    router.delegate(intentData);
    IERC721(pm).approve(address(router), uniV4TokenId);

    ActionData memory actionData = _getActionData(
      IPositionManager(pm).getPositionLiquidity(uniV4TokenId), 1000, 1000, false, token0, token1
    );
    vm.stopPrank();

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    vm.startPrank(caller);
    router.execute(intentData, daSignature, guardian, gdSignature, actionData);
    vm.stopPrank();

    vm.snapshotGasLastCall('test_execute_one_node_fee_on_native_and_erc20');
  }

  function testExecute_OneNode_FeeOnOneToken() public {
    Node[] memory nodes = new Node[](1);
    nodes[0] = _createLeafNode(_createCondition(TIME_BASED));
    IntentData memory intentData = _getIntentData(false, nodes);

    vm.startPrank(mainAddress);
    router.delegate(intentData);
    IERC721(pm).approve(address(router), uniV4TokenId);

    ActionData memory actionData = _getActionData(
      IPositionManager(pm).getPositionLiquidity(uniV4TokenId), 1000, 0, false, token0, token1
    );
    vm.stopPrank();

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    vm.startPrank(caller);
    router.execute(intentData, daSignature, guardian, gdSignature, actionData);
    vm.stopPrank();

    vm.snapshotGasLastCall('test_execute_one_node_fee_on_one_token');
  }

  function testExecute_OneNode_NoFee() public {
    Node[] memory nodes = new Node[](1);
    nodes[0] = _createLeafNode(_createCondition(TIME_BASED));
    IntentData memory intentData = _getIntentData(false, nodes);

    vm.startPrank(mainAddress);
    router.delegate(intentData);
    IERC721(pm).approve(address(router), uniV4TokenId);

    ActionData memory actionData = _getActionData(
      IPositionManager(pm).getPositionLiquidity(uniV4TokenId), 0, 0, false, token0, token1
    );
    vm.stopPrank();

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    vm.startPrank(caller);
    router.execute(intentData, daSignature, guardian, gdSignature, actionData);
    vm.stopPrank();

    vm.snapshotGasLastCall('test_execute_one_node_no_fee');
  }

  function testExecuteSignedIntent_NoPermit_NoFe() public {
    Node[] memory nodes = new Node[](1);
    nodes[0] = _createLeafNode(_createCondition(TIME_BASED));
    IntentData memory intentData = _getIntentData(false, nodes);

    vm.startPrank(mainAddress);
    IERC721(pm).approve(address(router), uniV4TokenId);
    vm.stopPrank();

    ActionData memory actionData = _getActionData(
      IPositionManager(pm).getPositionLiquidity(uniV4TokenId), 0, 0, false, token0, token1
    );
    vm.stopPrank();

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    bytes memory maSignature = _getMASignature(intentData);

    vm.startPrank(caller);
    router.executeWithSignedIntent(
      intentData, maSignature, daSignature, guardian, gdSignature, actionData
    );
    vm.stopPrank();

    vm.snapshotGasLastCall('test_execute_signed_intent_no_permit_no_fee');
  }

  function testExecuteSignedIntent_WithPermit_NoFee() public {
    Node[] memory nodes = new Node[](1);
    nodes[0] = _createLeafNode(_createCondition(TIME_BASED));
    IntentData memory intentData = _getIntentData(true, nodes);

    ActionData memory actionData = _getActionData(
      IPositionManager(pm).getPositionLiquidity(uniV4TokenId), 0, 0, false, token0, token1
    );
    vm.stopPrank();

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    bytes memory maSignature = _getMASignature(intentData);

    vm.startPrank(caller);
    router.executeWithSignedIntent(
      intentData, maSignature, daSignature, guardian, gdSignature, actionData
    );
    vm.stopPrank();

    vm.snapshotGasLastCall('test_execute_signed_intent_with_permit_no_fee');
  }

  function testExecuteSignedIntent_ThreeNodes_WithPermit_NoFee() public {
    Node[] memory nodes = new Node[](3);
    nodes[1] = _createLeafNode(_createCondition(PRICE_BASED));
    nodes[2] = _createLeafNode(_createCondition(YIELD_BASED));

    uint256[] memory andChildren = new uint256[](2);
    andChildren[0] = 1;
    andChildren[1] = 2;
    nodes[0] = _createParentNode(andChildren, AND);

    IntentData memory intentData = _getIntentData(true, nodes);

    ActionData memory actionData = _getActionData(
      IPositionManager(pm).getPositionLiquidity(uniV4TokenId), 0, 0, false, token0, token1
    );

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    bytes memory maSignature = _getMASignature(intentData);

    vm.startPrank(caller);
    router.executeWithSignedIntent(
      intentData, maSignature, daSignature, guardian, gdSignature, actionData
    );
    vm.stopPrank();

    vm.snapshotGasLastCall('test_execute_signed_intent_three_nodes_with_permit_no_fee');
  }

  function testExecuteSignedIntent_FiveNodes_WithPermit_NoFee() public {
    Node[] memory nodes = new Node[](5);
    nodes[1] = _createLeafNode(_createCondition(PRICE_BASED));
    nodes[2] = _createLeafNode(_createCondition(YIELD_BASED));
    nodes[3] = _createLeafNode(_createCondition(TIME_BASED));
    nodes[4] = _createLeafNode(_createCondition(YIELD_BASED));

    uint256[] memory andChildren = new uint256[](4);
    andChildren[0] = 1;
    andChildren[1] = 2;
    andChildren[2] = 3;
    andChildren[3] = 4;
    nodes[0] = _createParentNode(andChildren, AND);

    IntentData memory intentData = _getIntentData(true, nodes);

    ActionData memory actionData = _getActionData(
      IPositionManager(pm).getPositionLiquidity(uniV4TokenId), 0, 0, false, token0, token1
    );

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    bytes memory maSignature = _getMASignature(intentData);

    vm.startPrank(caller);
    router.executeWithSignedIntent(
      intentData, maSignature, daSignature, guardian, gdSignature, actionData
    );
    vm.stopPrank();

    vm.snapshotGasLastCall('test_execute_signed_intent_five_nodes_with_permit_no_fee');
  }

  function testExecuteSignedIntent_WithPermit_FeeOnBothTokens() public {
    Node[] memory nodes = new Node[](1);
    nodes[0] = _createLeafNode(_createCondition(TIME_BASED));
    IntentData memory intentData = _getIntentData(true, nodes);

    ActionData memory actionData = _getActionData(
      IPositionManager(pm).getPositionLiquidity(uniV4TokenId), 1000, 1000, false, token0, token1
    );
    vm.stopPrank();

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    bytes memory maSignature = _getMASignature(intentData);

    vm.startPrank(caller);
    router.executeWithSignedIntent(
      intentData, maSignature, daSignature, guardian, gdSignature, actionData
    );
    vm.stopPrank();

    vm.snapshotGasLastCall('test_execute_signed_intent_with_permit_fee_on_both_tokens');
  }

  function testExecute_ThreeNodes_NoFee() public {
    Node[] memory nodes = new Node[](3);
    nodes[1] = _createLeafNode(_createCondition(PRICE_BASED));
    nodes[2] = _createLeafNode(_createCondition(YIELD_BASED));

    uint256[] memory andChildren = new uint256[](2);
    andChildren[0] = 1;
    andChildren[1] = 2;
    nodes[0] = _createParentNode(andChildren, AND);

    IntentData memory intentData = _getIntentData(false, nodes);

    vm.startPrank(mainAddress);
    router.delegate(intentData);
    IERC721(pm).approve(address(router), uniV4TokenId);

    ActionData memory actionData = _getActionData(
      IPositionManager(pm).getPositionLiquidity(uniV4TokenId), 0, 0, false, token0, token1
    );
    vm.stopPrank();

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    vm.startPrank(caller);
    router.execute(intentData, daSignature, guardian, gdSignature, actionData);
    vm.stopPrank();

    vm.snapshotGasLastCall('test_execute_three_nodes_no_fee');
  }

  function testExecute_FiveNodes_NoFee() public {
    Node[] memory nodes = new Node[](5);
    nodes[1] = _createLeafNode(_createCondition(PRICE_BASED));
    nodes[2] = _createLeafNode(_createCondition(YIELD_BASED));
    nodes[3] = _createLeafNode(_createCondition(TIME_BASED));
    nodes[4] = _createLeafNode(_createCondition(YIELD_BASED));
    uint256[] memory andChildren = new uint256[](4);
    andChildren[0] = 1;
    andChildren[1] = 2;
    andChildren[2] = 3;
    andChildren[3] = 4;
    nodes[0] = _createParentNode(andChildren, AND);

    IntentData memory intentData = _getIntentData(false, nodes);

    vm.startPrank(mainAddress);
    router.delegate(intentData);
    IERC721(pm).approve(address(router), uniV4TokenId);

    ActionData memory actionData = _getActionData(
      IPositionManager(pm).getPositionLiquidity(uniV4TokenId), 0, 0, false, token0, token1
    );
    vm.stopPrank();

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, actionData);

    vm.startPrank(caller);
    router.execute(intentData, daSignature, guardian, gdSignature, actionData);
    vm.stopPrank();

    vm.snapshotGasLastCall('test_execute_five_nodes_no_fee');
  }

  function _getActionData(
    uint256 liquidity,
    uint256 intentFeesPercent0,
    uint256 intentFeesPercent1,
    bool unwrap,
    address _token0,
    address _token1
  ) internal view returns (ActionData memory actionData) {
    bool toRouter = intentFeesPercent0 != 0 || intentFeesPercent1 != 0;

    bytes[] memory multiCalldata;
    if (!unwrap) {
      bytes memory actions;
      bytes[] memory params;

      actions = new bytes(2);
      params = new bytes[](2);

      actions[0] = bytes1(uint8(Actions.CL_DECREASE_LIQUIDITY));
      params[0] = abi.encode(uniV4TokenId, liquidity, 0, 0, '');
      actions[1] = bytes1(uint8(Actions.TAKE_PAIR));
      params[1] = abi.encode(_token0, _token1, toRouter ? address(router) : address(mainAddress));

      multiCalldata = new bytes[](2);
      multiCalldata[0] = abi.encodeWithSelector(
        ICLPositionManager.modifyLiquidities.selector,
        abi.encode(actions, params),
        type(uint256).max
      );
      multiCalldata[1] = abi.encodeWithSelector(
        IERC721.transferFrom.selector, address(forwarder), mainAddress, uniV4TokenId
      );
    } else {
      bytes memory actions = new bytes(5);
      bytes[] memory params = new bytes[](5);
      actions[0] = bytes1(uint8(Actions.CL_DECREASE_LIQUIDITY));
      params[0] = abi.encode(uniV4TokenId, liquidity, 0, 0, '');
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
        ICLPositionManager.modifyLiquidities.selector,
        abi.encode(actions, params),
        type(uint256).max
      );
      multiCalldata[1] = abi.encodeWithSelector(
        IERC721.transferFrom.selector, address(forwarder), mainAddress, uniV4TokenId
      );
    }

    actionData = ActionData({
      erc20Ids: new uint256[](0),
      erc20Amounts: new uint256[](0),
      erc721Ids: [uint256(0)].toMemoryArray(),
      actionSelectorId: 0,
      approvalFlags: 0,
      actionCalldata: abi.encode(multiCalldata),
      hookActionData: abi.encode(
        0, 0.1 ether, 0.1 ether, liquidity, unwrap, intentFeesPercent0 << 128 | intentFeesPercent1
      ),
      extraData: '',
      deadline: block.timestamp + 1 days,
      nonce: 0
    });
  }

  function _createParentNode(uint256[] memory children, OperationType opType)
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

  function _createLeafNode(Condition memory condition) internal pure returns (Node memory) {
    uint256[] memory emptyChildren = new uint256[](0);
    return Node({
      operationType: AND, // doesn't matter for leaf
      condition: condition,
      childrenIndexes: emptyChildren
    });
  }

  function _createCondition(ConditionType conditionType) internal view returns (Condition memory) {
    if (ConditionType.unwrap(conditionType) == ConditionType.unwrap(PRICE_BASED)) {
      return Condition({
        conditionType: PRICE_BASED,
        data: abi.encode(PriceCondition({minPrice: 0, maxPrice: type(uint256).max}))
      });
    } else if (ConditionType.unwrap(conditionType) == ConditionType.unwrap(YIELD_BASED)) {
      return Condition({
        conditionType: YIELD_BASED,
        data: abi.encode(
          YieldCondition({
            targetYield: 1000, // 0.1%
            initialAmounts: (uint256(1 ether) << 128) | uint256(1 ether)
          })
        )
      });
    } else {
      return Condition({
        conditionType: TIME_BASED,
        data: abi.encode(
          TimeCondition({startTimestamp: block.timestamp - 100, endTimestamp: block.timestamp + 100})
        )
      });
    }
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
    hookData.maxFees[0] = (uint256(1_000_000) << 128) | 1_000_000;
    hookData.nodes = new Node[][](1);
    hookData.nodes[0] = nodes;

    hookData.recipient = mainAddress;

    address[] memory actionContracts = new address[](1);
    actionContracts[0] = address(pm);

    bytes4[] memory actionSelectors = new bytes4[](1);
    actionSelectors[0] = IUniswapV3PM.multicall.selector;

    IntentCoreData memory coreData = IntentCoreData({
      mainAddress: mainAddress,
      delegatedAddress: delegatedAddress,
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

  function _getPermitData(uint256 tokenId) internal view returns (bytes memory permitData) {
    bytes32 digest =
      Permit.uniswapV4Permit(pm, address(router), tokenId, 0, block.timestamp + 1 days);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(mainAddressKey, digest);
    bytes memory signature = abi.encodePacked(r, s, v);

    permitData = abi.encode(block.timestamp + 1 days, 0, signature);
  }
}
