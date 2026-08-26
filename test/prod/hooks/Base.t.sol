// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {TimeCondition} from 'src/hooks/base/BaseConditionalHook.sol';
import {
  BaseTickBasedRemoveLiquidityHook
} from 'src/hooks/base/BaseTickBasedRemoveLiquidityHook.sol';

import {KSSmartIntentHasher} from 'src/KSSmartIntentHasher.sol';
import {KSSmartIntentRouter} from 'src/KSSmartIntentRouter.sol';
import {IUniswapV3PM} from 'src/interfaces/uniswapv3/IUniswapV3PM.sol';
import {LiquidityAmounts} from 'src/libraries/uniswapv4/LiquidityAmounts.sol';
import {TickMath} from 'src/libraries/uniswapv4/TickMath.sol';

import {ActionData} from 'src/types/ActionData.sol';
import {Condition, ConditionType, Node, OperationType} from 'src/types/ConditionTree.sol';
import {ERC20Data} from 'src/types/ERC20Data.sol';
import {ERC721Data} from 'src/types/ERC721Data.sol';
import {FeeConfig, FeeInfo} from 'src/types/FeeInfo.sol';
import {IntentCoreData} from 'src/types/IntentCoreData.sol';
import {IntentData} from 'src/types/IntentData.sol';
import {TokenData} from 'src/types/TokenData.sol';

import 'ks-common-sc/script/Base.s.sol';

import {stdJson} from 'forge-std/StdJson.sol';
import {Test} from 'forge-std/Test.sol';
import {console} from 'forge-std/console.sol';

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IERC721} from 'openzeppelin-contracts/contracts/token/ERC721/IERC721.sol';

/// @dev One entry of `action-contracts.json`. Fields are alphabetical: `vm.parseJson` decodes JSON
/// objects in that order, so `address` comes before `name`.
struct ActionContract {
  address addr;
  string name;
}

abstract contract Base is Test, BaseScript {
  using stdJson for string;

  bytes32 constant ACTION_CONTRACT_ROLE = keccak256('ACTION_CONTRACT_ROLE');
  bytes32 constant GUARDIAN_ROLE = keccak256('GUARDIAN_ROLE');
  ConditionType constant TIME_BASED = ConditionType.wrap(keccak256('TIME_BASED'));

  uint256 constant MAX_FEE_PERCENT = 20_000; // 2%
  uint256 constant INTENT_FEE_PERCENT = 10_000; // 1%

  KSSmartIntentRouter router;
  /// @dev The hasher the router deployed in its own constructor, so intents are hashed exactly
  /// the way the deployed router hashes them.
  KSSmartIntentHasher hasher;
  address forwarder;
  address guardian;

  address hook;
  address positionManager;
  address token0;
  address token1;
  int24 tickLower;
  int24 tickUpper;

  uint256 tokenId;
  /// @dev A second real position, so the mismatch check compares two positions that both exist.
  uint256 otherTokenId;
  uint128 positionLiquidity;

  address mainAddress;
  uint256 mainAddressKey;
  address delegatedAddress;
  uint256 delegatedKey;
  address protocolRecipient = makeAddr('protocolRecipient');
  uint256 nextNonce;

  /**
   * @notice Checks every chain this hook is deployed to, taken from its entry in the registry, so
   * deploying the hook to a new chain makes this run there without anyone adding a test.
   */
  function test_removeLiquidity() public {
    uint256[] memory chains = _deployedChains(_hookConfigKey());
    assertGt(chains.length, 0, 'the hook is not deployed on any chain');

    string[] memory names = _positionManagerNames();

    for (uint256 i = 0; i < chains.length; i++) {
      console.log('=== chain %s ===', vm.toString(chains[i]));
      _fork(chains[i]);

      uint256 checked;
      for (uint256 j = 0; j < names.length; j++) {
        address found = _findActionContract(names[j]);
        if (found == address(0)) continue;

        console.log('  %s %s', names[j], vm.toString(found));
        positionManager = found;
        _test();
        checked++;
      }

      assertGt(checked, 0, 'the hook is deployed here but the router whitelists no manager for it');
    }
  }

  function _fork(uint256 chainId) internal {
    vm.createSelectFork(_rpcUrl(chainId));
    assertEq(block.chainid, chainId, 'the RPC URL points at a different chain');

    (mainAddress, mainAddressKey) = makeAddrAndKey('prod.mainAddress');
    (delegatedAddress, delegatedKey) = makeAddrAndKey('prod.delegatedKey');
    nextNonce = 0;

    router = KSSmartIntentRouter(payable(_readAddress('router')));
    assertGt(address(router).code.length, 0, 'router is not deployed on this chain');

    hasher = KSSmartIntentHasher(vm.computeCreateAddress(address(router), 1));
    forwarder = _readAddress('forwarder');
    guardian = _liveGuardian();

    hook = _readAddress(_hookConfigKey());
    assertGt(hook.code.length, 0, 'hook is not deployed on this chain');

    vm.label(address(router), 'DeployedRouter');
    vm.label(forwarder, 'DeployedForwarder');
    vm.label(guardian, 'LiveGuardian');
    vm.label(hook, 'DeployedHook');
  }

  /**
   * @dev Runs the whole check for whichever chain `_fork` selected. Each part gets a freshly
   * minted position: an intent can only be delegated once, and the first part empties the position
   * it operates on.
   */
  function _test() internal {
    _prepareData();

    _testRemoveLiquidity();

    (tokenId, positionLiquidity) = _mintPosition();
    _testNonceCannotBeReplayed();

    (tokenId, positionLiquidity) = _mintPosition();
    _testHookRejectsMismatchedPosition();

    (tokenId, positionLiquidity) = _mintPosition();
    _testHookRejectsFeesAboveTheCeiling();
  }

  function _prepareData() internal {
    assertGt(positionManager.code.length, 0, 'position manager is not deployed on this chain');
    vm.label(positionManager, 'PositionManager');

    assertTrue(
      router.hasRole(ACTION_CONTRACT_ROLE, positionManager),
      'the position manager is not an approved action contract on this chain'
    );

    _setUpPool();

    (tokenId, positionLiquidity) = _mintPosition();
    (otherTokenId,) = _mintPosition();
  }

  function _testRemoveLiquidity() private {
    (uint256 expected0, uint256 expected1) = _expectedAmounts(positionLiquidity);
    uint256 fee0 = (expected0 * INTENT_FEE_PERCENT) / 1e6;
    uint256 fee1 = (expected1 * INTENT_FEE_PERCENT) / 1e6;

    IntentData memory intentData = _buildIntent(tokenId);
    _approveAndDelegate(intentData);

    uint256[2] memory ownerBefore =
      [IERC20(token0).balanceOf(mainAddress), IERC20(token1).balanceOf(mainAddress)];
    uint256[2] memory protocolBefore =
      [IERC20(token0).balanceOf(protocolRecipient), IERC20(token1).balanceOf(protocolRecipient)];

    vm.expectEmit(false, false, false, true, hook);
    emit BaseTickBasedRemoveLiquidityHook.LiquidityRemoved(
      positionManager, tokenId, positionLiquidity
    );
    _execute(intentData, _buildActionData(positionLiquidity));

    assertEq(
      IERC20(token0).balanceOf(mainAddress) - ownerBefore[0],
      expected0 - fee0,
      'token0 was not returned to the position owner'
    );
    assertEq(
      IERC20(token1).balanceOf(mainAddress) - ownerBefore[1],
      expected1 - fee1,
      'token1 was not returned to the position owner'
    );
    assertEq(
      IERC20(token0).balanceOf(protocolRecipient) - protocolBefore[0],
      fee0,
      'token0 intent fee was not collected'
    );
    assertEq(
      IERC20(token1).balanceOf(protocolRecipient) - protocolBefore[1],
      fee1,
      'token1 intent fee was not collected'
    );
    assertEq(IERC721(positionManager).ownerOf(tokenId), mainAddress, 'position was not returned');
  }

  function _testNonceCannotBeReplayed() private {
    IntentData memory intentData = _buildIntent(tokenId);
    _approveAndDelegate(intentData);

    ActionData memory actionData = _buildActionData(positionLiquidity / 2);
    _execute(intentData, actionData);

    bytes memory signature = _delegatedKeySignature(intentData, actionData);
    vm.expectRevert();
    vm.prank(guardian);
    router.execute(intentData, signature, guardian, '', actionData);
  }

  function _testHookRejectsMismatchedPosition() private {
    IntentData memory intentData = _buildIntent(tokenId);
    BaseTickBasedRemoveLiquidityHook.RemoveLiquidityHookData memory hookData =
      _buildHookData(tokenId);
    hookData.nftIds[0] = otherTokenId;
    intentData.coreData.hookIntentData = abi.encode(hookData);

    _approveAndDelegate(intentData);
    _expectExecuteRevert(
      intentData,
      _buildActionData(positionLiquidity),
      BaseTickBasedRemoveLiquidityHook.InvalidERC721Data.selector
    );
  }

  function _testHookRejectsFeesAboveTheCeiling() private {
    IntentData memory intentData = _buildIntent(tokenId);
    _approveAndDelegate(intentData);

    ActionData memory actionData = _buildActionData(positionLiquidity);
    actionData.hookActionData = abi.encode(
      uint256(0),
      uint256(0),
      uint256(0),
      uint256(positionLiquidity),
      false,
      ((MAX_FEE_PERCENT + 1) << 128) | (MAX_FEE_PERCENT + 1)
    );

    _expectExecuteRevert(
      intentData, actionData, BaseTickBasedRemoveLiquidityHook.ExceedMaxFeesPercent.selector
    );
  }

  function _approveAndDelegate(IntentData memory intentData) internal {
    vm.startPrank(mainAddress);
    IERC721(positionManager).approve(address(router), tokenId);
    router.delegate(intentData);
    vm.stopPrank();
  }

  function _execute(IntentData memory intentData, ActionData memory actionData) internal {
    bytes memory signature = _delegatedKeySignature(intentData, actionData);

    vm.prank(guardian);
    router.execute(intentData, signature, guardian, '', actionData);
  }

  function _expectExecuteRevert(
    IntentData memory intentData,
    ActionData memory actionData,
    bytes4 expectedError
  ) internal {
    bytes memory signature = _delegatedKeySignature(intentData, actionData);

    vm.expectRevert(expectedError);
    vm.prank(guardian);
    router.execute(intentData, signature, guardian, '', actionData);
  }

  function _delegatedKeySignature(IntentData memory intentData, ActionData memory actionData)
    internal
    view
    returns (bytes memory)
  {
    bytes32 witnessHash =
      _hashTypedData(hasher.hashActionWitness(_intentHash(intentData), actionData));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(delegatedKey, witnessHash);

    return abi.encodePacked(r, s, v);
  }

  function _intentHash(IntentData memory intentData) internal view returns (bytes32) {
    return _hashTypedData(hasher.hashIntentData(intentData));
  }

  function _hashTypedData(bytes32 structHash) internal view returns (bytes32) {
    return keccak256(abi.encodePacked(hex'1901', router.DOMAIN_SEPARATOR(), structHash));
  }

  function _buildIntent(uint256 positionId) internal returns (IntentData memory intentData) {
    address[] memory intentActionContracts = new address[](1);
    intentActionContracts[0] = positionManager;
    bytes4[] memory actionSelectors = new bytes4[](1);
    actionSelectors[0] = IUniswapV3PM.multicall.selector;

    IntentCoreData memory coreData = IntentCoreData({
      mainAddress: mainAddress,
      signatureVerifier: address(0),
      delegatedKey: abi.encode(delegatedAddress),
      actionContracts: intentActionContracts,
      actionSelectors: actionSelectors,
      hook: hook,
      hookIntentData: abi.encode(_buildHookData(positionId))
    });

    TokenData memory tokenData;
    tokenData.erc20Data = new ERC20Data[](0);
    tokenData.erc721Data = new ERC721Data[](1);
    tokenData.erc721Data[0] =
      ERC721Data({token: positionManager, tokenId: positionId, permitData: ''});

    intentData = IntentData({coreData: coreData, tokenData: tokenData, extraData: ''});
  }

  function _buildHookData(uint256 positionId)
    internal
    returns (BaseTickBasedRemoveLiquidityHook.RemoveLiquidityHookData memory hookData)
  {
    hookData.nftAddresses = new address[](1);
    hookData.nftAddresses[0] = positionManager;
    hookData.nftIds = new uint256[](1);
    hookData.nftIds[0] = positionId;
    hookData.maxFees = new uint256[](1);
    hookData.maxFees[0] = (MAX_FEE_PERCENT << 128) | MAX_FEE_PERCENT;
    hookData.recipient = mainAddress;
    hookData.additionalData = _hookAdditionalData();

    Node[] memory nodes = new Node[](1);
    nodes[0] = Node({
      operationType: OperationType.AND,
      condition: Condition({
        conditionType: TIME_BASED,
        data: abi.encode(
          TimeCondition({
            startTimestamp: block.timestamp - 1, endTimestamp: block.timestamp + 1 days
          })
        )
      }),
      childrenIndexes: new uint256[](0)
    });
    hookData.nodes = new Node[][](1);
    hookData.nodes[0] = nodes;
  }

  function _buildActionData(uint256 liquidityToRemove)
    internal
    returns (ActionData memory actionData)
  {
    FeeInfo memory feeInfo;
    feeInfo.protocolRecipient = protocolRecipient;
    feeInfo.partnerFeeConfigs = new FeeConfig[][](2);
    feeInfo.partnerFeeConfigs[0] = new FeeConfig[](0);
    feeInfo.partnerFeeConfigs[1] = new FeeConfig[](0);

    actionData = ActionData({
      erc20Ids: new uint256[](0),
      erc20Amounts: new uint256[](0),
      erc721Ids: new uint256[](1),
      feeInfo: feeInfo,
      approvalFlags: type(uint256).max,
      actionSelectorId: 0,
      actionCalldata: abi.encode(_removeLiquidityCalls(liquidityToRemove)),
      // index, unclaimed fee0, unclaimed fee1, liquidity, wrapOrUnwrap, packed intent fees
      hookActionData: abi.encode(
        uint256(0),
        uint256(0),
        uint256(0),
        liquidityToRemove,
        false,
        (INTENT_FEE_PERCENT << 128) | INTENT_FEE_PERCENT
      ),
      extraData: '',
      deadline: block.timestamp + 1 days,
      nonce: nextNonce++
    });
  }

  /// @dev What the position is worth right now, valued the way the hook values it.
  function _expectedAmounts(uint256 liquidity)
    internal
    view
    returns (uint256 amount0, uint256 amount1)
  {
    (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
      _currentSqrtPrice(),
      TickMath.getSqrtRatioAtTick(tickLower),
      TickMath.getSqrtRatioAtTick(tickUpper),
      uint128(liquidity)
    );
  }

  /// @dev The key in `hook-configs.json` that exports this hook's address.
  function _hookConfigKey() internal view virtual returns (string memory);

  /**
   * @dev The names in `action-contracts.json` this check can drive. A hook works against every
   * position manager of its protocol family - the Uniswap V3 hook drives the Pancake V3 and
   * SushiSwap V3 managers too - and each one the router whitelists is checked.
   */
  function _positionManagerNames() internal pure virtual returns (string[] memory);

  /// @dev Resolves the pool and the token pair the check will use.
  function _setUpPool() internal virtual;

  /// @dev Creates a position owned by `mainAddress` that spans the current tick.
  function _mintPosition() internal virtual returns (uint256 newTokenId, uint128 liquidity);

  /// @dev The position manager multicall that removes liquidity and returns the position.
  function _removeLiquidityCalls(uint256 liquidityToRemove)
    internal
    view
    virtual
    returns (bytes[] memory calls);

  function _currentSqrtPrice() internal view virtual returns (uint160);

  /// @dev Only the Uniswap V3 hook needs anything here: the pool addresses.
  function _hookAdditionalData() internal view virtual returns (bytes memory) {
    return '';
  }

  // ---------------------------------------------------------------------------------------------
  // Deployment registry. Addresses are read with `BaseScript`'s helpers so they resolve exactly
  // the way the deploy scripts resolve them. Only what `BaseScript` has no notion of lives here.
  // ---------------------------------------------------------------------------------------------

  /// @dev The chain ids a registry file has an entry for. Iterating this rather than a
  /// hand-written list is what makes deploying to a new chain enough for it to be checked.
  function _deployedChains(string memory name) internal view returns (uint256[] memory ids) {
    string[] memory keys = vm.parseJsonKeys(_getJsonString(name), '$');

    ids = new uint256[](keys.length);
    uint256 count;
    for (uint256 i = 0; i < keys.length; i++) {
      uint256 chainId = vm.parseUint(keys[i]);
      if (chainId == 0) continue;
      ids[count++] = chainId;
    }

    assembly ('memory-safe') {
      mstore(ids, count)
    }
  }

  /**
   * @dev `BaseScript._getRpcUrl` falls back to returning the key itself, which would fork against
   * a nonsense URL. A chain with a deployment and no node URL is a gap, so this fails instead.
   */
  function _rpcUrl(uint256 chainId) internal view returns (string memory url) {
    string memory key = string.concat('RPC_', vm.toString(chainId));

    url = vm.envOr(key, string(''));
    require(bytes(url).length > 0, string.concat(key, ' is not set'));
  }

  /// @dev What the router whitelists on this chain, with the name each address is registered as.
  function actionContracts() internal view returns (ActionContract[] memory) {
    return abi.decode(
      vm.parseJson(_getJsonString('action-contracts'), _toDotChainId(block.chainid)),
      (ActionContract[])
    );
  }

  /// @dev The address the router whitelists on this chain under `name`, or zero when this chain
  /// has none - not every protocol is on every chain.
  function _findActionContract(string memory name) internal view returns (address) {
    ActionContract[] memory entries = actionContracts();

    for (uint256 i = 0; i < entries.length; i++) {
      if (keccak256(bytes(entries[i].name)) == keccak256(bytes(name))) return entries[i].addr;
    }

    return address(0);
  }

  function _liveGuardian() internal returns (address) {
    address[] memory guardians = _readAddressArray('router-guardians');
    for (uint256 i = 0; i < guardians.length; i++) {
      if (router.hasRole(GUARDIAN_ROLE, guardians[i])) return guardians[i];
    }
    revert('no configured guardian holds GUARDIAN_ROLE on the deployed router');
  }
}
