// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../Base.t.sol';

import 'src/hooks/base/BaseHook.sol';
import 'src/hooks/base/BaseTickBasedZapMigrateHook.sol';
import {
  KSZapMigrateUniswapV3Hook as KSZapMigratePancakeV4CLHook
} from 'src/hooks/zap-migrate/KSZapMigratePancakeV4CLHook.sol';

import {IAllowanceTransfer} from 'ks-common-sc/src/interfaces/IAllowanceTransfer.sol';
import {TokenHelper} from 'ks-common-sc/src/libraries/token/TokenHelper.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {ICLPoolManager} from 'src/interfaces/pancakev4/ICLPoolManager.sol';
import {ICLPositionManager} from 'src/interfaces/pancakev4/ICLPositionManager.sol';
import {IVault} from 'src/interfaces/pancakev4/IVault.sol';
import {Actions, BalanceDelta, PoolId, PoolKey} from 'src/interfaces/pancakev4/Types.sol';
import {LiquidityAmounts} from 'src/libraries/uniswapv4/LiquidityAmounts.sol';
import {TickMath} from 'src/libraries/uniswapv4/TickMath.sol';

import './ZapMigrateFuzzParams.sol';

contract ZapMigratePancakeV4CLTest is BaseTest {
  using ArraysHelper for *;
  using TokenHelper for address;

  ICLPositionManager internal constant PM =
    ICLPositionManager(0x55f4c8abA71A1e923edC303eb4fEfF14608cC226);

  address internal constant TOKEN0 = address(0);
  address internal constant TOKEN1 = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
  address internal constant POOL_HOOKS = 0x32C59D556B16DB81DFc32525eFb3CB257f7e493d;
  address internal constant CL_POOL_MANAGER = 0xa0FfB9c1CE1Fe56963B0321B32E7A0302114058b;
  address internal constant VAULT_ADDRESS = 0x238a358808379702088667322f80aC48bAd5e6c4;
  address internal constant PERMIT2 = 0x31c2F6fcFf4F8759b3Bd5Bf0e1084A055615c768;
  uint24 internal constant POOL_FEE = 8_388_608;
  int24 internal constant TICK_SPACING = 10;
  bytes32 internal constant POOL_PARAMETERS =
    0x00000000000000000000000000000000000000000000000000000000000a00c2;

  uint256 internal constant FEE_PRECISION = 1_000_000;

  KSZapMigratePancakeV4CLHook internal zapHook;
  ICLPoolManager internal poolManager;
  IVault internal vault;

  struct PositionContext {
    address token0;
    address token1;
    int24 tickLower;
    int24 tickUpper;
    int24 currentTick;
    bytes32 poolUniqueId;
  }

  struct SwapLockData {
    int24 targetTick;
    bool zeroForOne;
  }

  struct SuccessMigrationSetup {
    IntentData intentData;
    ActionData actionData0;
    int24 targetTickForSecondMigration;
    uint256 amount0Desired0;
    uint256 amount1Desired0;
    uint256 amount0Desired1;
    uint256 amount1Desired1;
    uint24 actionFee01;
    uint24 actionFee11;
  }

  function _selectFork() public override {
    FORK_BLOCK = 56_756_230;
    vm.createSelectFork('bsc_mainnet', FORK_BLOCK);
  }

  function setUp() public override {
    super.setUp();
    poolManager = PM.clPoolManager();
    vault = IVault(VAULT_ADDRESS);
    zapHook = new KSZapMigratePancakeV4CLHook([address(router)].toMemoryArray());
  }

  function testFuzz_ZapMigratePancakeV4CL_Success(ZapMigrateFuzzParams memory fuzz) public {
    (uint256 oldNftId, PositionContext memory pos) = _mintFreshPosition(
      address(forwarder), fuzz.mintRangeMultiplier, fuzz.mintAmount0Desired, fuzz.mintAmount1Desired
    );
    SuccessMigrationSetup memory setup = _prepareSuccessFirstMigration(fuzz, oldNftId, pos);

    deal(address(mockActionContract), setup.amount0Desired0);
    deal(pos.token1, address(mockActionContract), setup.amount1Desired0);

    vm.prank(address(forwarder));
    router.delegate(setup.intentData);
    _executeDelegated(setup.intentData, setup.actionData0);

    bytes32 intentHash = router.hashTypedIntentData(setup.intentData);
    uint256 firstMigratedNftId = zapHook.nftIds(intentHash);
    assertTrue(firstMigratedNftId != 0, 'first migrated nft id is not recorded');
    assertTrue(firstMigratedNftId != oldNftId, 'first migrated nft id must differ from old nft id');
    assertEq(
      PM.ownerOf(firstMigratedNftId), address(forwarder), 'first migrated nft owner mismatch'
    );

    vm.prank(address(forwarder));
    PM.approve(address(mockActionContract), firstMigratedNftId);
    vm.prank(address(forwarder));
    PM.approve(address(router), oldNftId);

    PositionContext memory posBeforeSwap = _positionContext(firstMigratedNftId);
    int24 targetTick = _clampInt24(
      setup.targetTickForSecondMigration, posBeforeSwap.tickLower, posBeforeSwap.tickUpper
    );
    PositionContext memory posAfterSwap =
      _movePoolTickToTarget(firstMigratedNftId, posBeforeSwap, targetTick);

    (int24 newTickLower1, int24 newTickUpper1) =
      _newTicks(posAfterSwap.currentTick, fuzz.newRangeMultiplier);
    ActionData memory actionData1 = _buildActionData(
      firstMigratedNftId,
      newTickLower1,
      newTickUpper1,
      address(forwarder),
      setup.amount0Desired1,
      setup.amount1Desired1,
      setup.actionFee01,
      setup.actionFee11
    );
    actionData1.nonce = 1;

    deal(address(mockActionContract), setup.amount0Desired1);
    deal(posAfterSwap.token1, address(mockActionContract), setup.amount1Desired1);

    _executeDelegated(setup.intentData, actionData1);

    uint256 secondMigratedNftId = zapHook.nftIds(intentHash);

    assertTrue(secondMigratedNftId != 0, 'second migrated nft id is not recorded');
    assertTrue(
      secondMigratedNftId != firstMigratedNftId,
      'second migrated nft id must differ from first migrated nft id'
    );
    assertEq(PM.ownerOf(oldNftId), address(forwarder), 'old nft owner mismatch');
    assertEq(
      PM.ownerOf(firstMigratedNftId), address(forwarder), 'first migrated nft owner mismatch'
    );
    assertEq(
      PM.ownerOf(secondMigratedNftId), address(forwarder), 'second migrated nft owner mismatch'
    );
  }

  function testFuzz_Revert_InvalidTokenData(ZapMigrateFuzzParams memory fuzz) public {
    (uint256 oldNftId, PositionContext memory pos) = _mintFreshPosition(
      address(forwarder), fuzz.mintRangeMultiplier, fuzz.mintAmount0Desired, fuzz.mintAmount1Desired
    );
    (int24 newTickLower, int24 newTickUpper) = _newTicks(pos.currentTick, fuzz.newRangeMultiplier);

    uint256 amount0Desired = bound(fuzz.actionAmount0Desireds[0], 0.01 ether, 1 ether);
    uint256 amount1Desired = bound(fuzz.actionAmount1Desireds[0], 100e6, 2000e6);

    BaseTickBasedZapMigrateHook.ZapMigrateHookData memory hookData =
      _successHookData(fuzz, oldNftId, pos, newTickLower, newTickUpper, 0, 0);
    IntentData memory intentData = _buildIntentData(address(forwarder), hookData, oldNftId);

    ActionData memory actionData = _buildActionData(
      oldNftId, newTickLower, newTickUpper, address(forwarder), amount0Desired, amount1Desired, 0, 0
    );
    actionData.erc20Ids = [uint256(0)].toMemoryArray();
    actionData.erc20Amounts = [bound(fuzz.invalidTokenErc20Amount, 0, 1e18)].toMemoryArray();

    vm.prank(address(forwarder));
    router.delegate(intentData);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData, actionData);

    vm.prank(caller);
    vm.expectRevert(BaseHook.InvalidTokenData.selector);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function testFuzz_Revert_TooLargeDistanceFromTickBoundaries(ZapMigrateFuzzParams memory fuzz)
    public
  {
    (uint256 oldNftId, PositionContext memory pos) = _mintFreshPosition(
      address(forwarder), fuzz.mintRangeMultiplier, fuzz.mintAmount0Desired, fuzz.mintAmount1Desired
    );
    (int24 newTickLower, int24 newTickUpper) = _newTicks(pos.currentTick, fuzz.newRangeMultiplier);

    BaseTickBasedZapMigrateHook.ZapMigrateHookData memory hookData =
      _successHookData(fuzz, oldNftId, pos, newTickLower, newTickUpper, 0, 0);
    hookData.maxDistanceFromLowerTickBeforeMigration = (pos.currentTick - pos.tickLower) - 1;
    hookData.maxDistanceFromUpperTickBeforeMigration = (pos.tickUpper - pos.currentTick) - 1;

    IntentData memory intentData = _buildIntentData(address(forwarder), hookData, oldNftId);
    ActionData memory actionData = _buildActionData(
      oldNftId, newTickLower, newTickUpper, address(forwarder), 0.1 ether, 500e6, 0, 0
    );

    vm.expectRevert(BaseTickBasedZapMigrateHook.TooLargeDistanceFromTickBoundaries.selector);
    vm.prank(address(router));
    zapHook.beforeExecution(bytes32(0), intentData, actionData);
  }

  function testFuzz_Revert_InvalidOwner(ZapMigrateFuzzParams memory fuzz) public {
    (uint256 oldNftId, PositionContext memory pos) = _mintFreshPosition(
      mainAddress, fuzz.mintRangeMultiplier, fuzz.mintAmount0Desired, fuzz.mintAmount1Desired
    );
    (int24 newTickLower, int24 newTickUpper) = _newTicks(pos.currentTick, fuzz.newRangeMultiplier);

    uint256 amount0Desired = bound(fuzz.actionAmount0Desireds[0], 0.1 ether, 5 ether);
    uint256 amount1Desired = bound(fuzz.actionAmount1Desireds[0], 100e6, 20_000e6);

    BaseTickBasedZapMigrateHook.ZapMigrateHookData memory hookData =
      _successHookData(fuzz, oldNftId, pos, newTickLower, newTickUpper, 0, 0);
    IntentData memory intentData = _buildIntentData(mainAddress, hookData, oldNftId);
    ActionData memory actionData = _buildActionData(
      oldNftId, newTickLower, newTickUpper, mainAddress, amount0Desired, amount1Desired, 0, 0
    );

    deal(address(mockActionContract), amount0Desired);
    deal(pos.token1, address(mockActionContract), amount1Desired);

    vm.prank(mainAddress);
    router.delegate(intentData);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData, actionData);

    vm.prank(caller);
    vm.expectRevert(BaseTickBasedZapMigrateHook.InvalidOwner.selector);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function testFuzz_Revert_ExceedMaxFeesPercent(ZapMigrateFuzzParams memory fuzz) public {
    (uint256 oldNftId, PositionContext memory pos) = _mintFreshPosition(
      address(forwarder), fuzz.mintRangeMultiplier, fuzz.mintAmount0Desired, fuzz.mintAmount1Desired
    );
    (int24 newTickLower, int24 newTickUpper) = _newTicks(pos.currentTick, fuzz.newRangeMultiplier);

    uint256 amount0Desired = bound(fuzz.actionAmount0Desireds[0], 0.1 ether, 5 ether);
    uint256 amount1Desired = bound(fuzz.actionAmount1Desireds[0], 100e6, 20_000e6);
    uint24 actionFee0 = uint24(bound(fuzz.actionFee0s[0], 1, FEE_PRECISION));
    uint24 actionFee1 = uint24(bound(fuzz.actionFee1s[0], 1, FEE_PRECISION));

    BaseTickBasedZapMigrateHook.ZapMigrateHookData memory hookData =
      _successHookData(fuzz, oldNftId, pos, newTickLower, newTickUpper, actionFee0, actionFee1);
    hookData.maxFee0 = bound(fuzz.maxFee0, 0, uint256(actionFee0 - 1));
    hookData.maxFee1 = bound(fuzz.maxFee1, 0, uint256(actionFee1 - 1));

    IntentData memory intentData = _buildIntentData(address(forwarder), hookData, oldNftId);
    ActionData memory actionData = _buildActionData(
      oldNftId,
      newTickLower,
      newTickUpper,
      address(forwarder),
      amount0Desired,
      amount1Desired,
      actionFee0,
      actionFee1
    );

    deal(address(mockActionContract), amount0Desired);
    deal(pos.token1, address(mockActionContract), amount1Desired);

    vm.prank(address(forwarder));
    router.delegate(intentData);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData, actionData);

    vm.prank(caller);
    vm.expectRevert(BaseTickBasedZapMigrateHook.ExceedMaxFeesPercent.selector);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function testFuzz_Revert_TooSmallDistanceFromTickBoundaries(ZapMigrateFuzzParams memory fuzz)
    public
  {
    (uint256 oldNftId, PositionContext memory pos) = _mintFreshPosition(
      address(forwarder), fuzz.mintRangeMultiplier, fuzz.mintAmount0Desired, fuzz.mintAmount1Desired
    );
    (int24 newTickLower, int24 newTickUpper) = _newTicks(pos.currentTick, fuzz.newRangeMultiplier);

    BaseTickBasedZapMigrateHook.ZapMigrateHookData memory hookData =
      _successHookData(fuzz, oldNftId, pos, newTickLower, newTickUpper, 0, 0);
    int24 requiredExtraDistance = int24(uint24(_clamp(fuzz.samplePositionIndex, 1, 10_000)));
    hookData.minDistanceFromLowerTickAfterMigration =
      (pos.currentTick - newTickLower) + requiredExtraDistance;

    IntentData memory intentData = _buildIntentData(address(forwarder), hookData, oldNftId);
    ActionData memory actionData = _buildActionData(
      oldNftId, newTickLower, newTickUpper, address(forwarder), 0.1 ether, 500e6, 0, 0
    );

    deal(address(mockActionContract), 0.1 ether);
    deal(pos.token1, address(mockActionContract), 500e6);

    vm.prank(address(forwarder));
    router.delegate(intentData);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData, actionData);

    vm.prank(caller);
    vm.expectRevert(BaseTickBasedZapMigrateHook.TooSmallDistanceFromTickBoundaries.selector);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function testFuzz_Revert_TooSmallTickRangeLength(ZapMigrateFuzzParams memory fuzz) public {
    (uint256 oldNftId, PositionContext memory pos) = _mintFreshPosition(
      address(forwarder), fuzz.mintRangeMultiplier, fuzz.mintAmount0Desired, fuzz.mintAmount1Desired
    );
    (int24 newTickLower, int24 newTickUpper) = _newTicks(pos.currentTick, fuzz.newRangeMultiplier);
    int24 range = newTickUpper - newTickLower;

    BaseTickBasedZapMigrateHook.ZapMigrateHookData memory hookData =
      _successHookData(fuzz, oldNftId, pos, newTickLower, newTickUpper, 0, 0);
    int24 minIncrease = int24(uint24(_clamp(fuzz.invalidTokenErc20Amount, 1, 10_000)));
    hookData.minTickRangeLength = range + minIncrease;

    IntentData memory intentData = _buildIntentData(address(forwarder), hookData, oldNftId);
    ActionData memory actionData = _buildActionData(
      oldNftId, newTickLower, newTickUpper, address(forwarder), 0.1 ether, 500e6, 0, 0
    );

    deal(address(mockActionContract), 0.1 ether);
    deal(pos.token1, address(mockActionContract), 500e6);

    vm.prank(address(forwarder));
    router.delegate(intentData);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData, actionData);

    vm.prank(caller);
    vm.expectRevert(BaseTickBasedZapMigrateHook.TooSmallTickRangeLength.selector);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function testFuzz_Revert_TooLargeTickRangeLength(ZapMigrateFuzzParams memory fuzz) public {
    (uint256 oldNftId, PositionContext memory pos) = _mintFreshPosition(
      address(forwarder), fuzz.mintRangeMultiplier, fuzz.mintAmount0Desired, fuzz.mintAmount1Desired
    );
    (int24 newTickLower, int24 newTickUpper) = _newTicks(pos.currentTick, fuzz.newRangeMultiplier);
    int24 range = newTickUpper - newTickLower;

    BaseTickBasedZapMigrateHook.ZapMigrateHookData memory hookData =
      _successHookData(fuzz, oldNftId, pos, newTickLower, newTickUpper, 0, 0);
    uint256 maxDecrease = uint256(uint24(range - 1));
    int24 decrease = int24(uint24(_clamp(fuzz.samplePositionIndex, 1, maxDecrease)));
    hookData.maxTickRangeLength = range - decrease;

    IntentData memory intentData = _buildIntentData(address(forwarder), hookData, oldNftId);
    ActionData memory actionData = _buildActionData(
      oldNftId, newTickLower, newTickUpper, address(forwarder), 0.1 ether, 500e6, 0, 0
    );

    deal(address(mockActionContract), 0.1 ether);
    deal(pos.token1, address(mockActionContract), 500e6);

    vm.prank(address(forwarder));
    router.delegate(intentData);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData, actionData);

    vm.prank(caller);
    vm.expectRevert(BaseTickBasedZapMigrateHook.TooLargeTickRangeLength.selector);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function testFuzz_Revert_InsufficientPositionValue(ZapMigrateFuzzParams memory fuzz) public {
    (uint256 oldNftId, PositionContext memory pos) = _mintFreshPosition(
      address(forwarder), fuzz.mintRangeMultiplier, fuzz.mintAmount0Desired, fuzz.mintAmount1Desired
    );
    (int24 newTickLower, int24 newTickUpper) = _newTicks(pos.currentTick, fuzz.newRangeMultiplier);

    BaseTickBasedZapMigrateHook.ZapMigrateHookData memory hookData =
      _successHookData(fuzz, oldNftId, pos, newTickLower, newTickUpper, 0, 0);
    hookData.minValueInToken0 = type(uint128).max + bound(fuzz.minValueInToken0, 1, 1e30);

    IntentData memory intentData = _buildIntentData(address(forwarder), hookData, oldNftId);
    ActionData memory actionData = _buildActionData(
      oldNftId, newTickLower, newTickUpper, address(forwarder), 0.1 ether, 500e6, 0, 0
    );

    deal(address(mockActionContract), 0.1 ether);
    deal(pos.token1, address(mockActionContract), 500e6);

    vm.prank(address(forwarder));
    router.delegate(intentData);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData, actionData);

    vm.prank(caller);
    vm.expectRevert(BaseTickBasedZapMigrateHook.InsufficientPositionValue.selector);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function testFuzz_Revert_InvalidPoolUniqueId(ZapMigrateFuzzParams memory fuzz) public {
    (uint256 nftId, PositionContext memory pos) = _mintFreshPosition(
      address(forwarder), fuzz.mintRangeMultiplier, fuzz.mintAmount0Desired, fuzz.mintAmount1Desired
    );

    BaseTickBasedZapMigrateHook.ZapMigrateHookData memory hookData = _minimalHookData(nftId);
    IntentData memory intentData = _buildIntentData(address(forwarder), hookData, nftId);

    bytes32 invalidPoolUniqueId =
      pos.poolUniqueId ^ bytes32(_clamp(fuzz.invalidTokenErc20Amount, 1, type(uint256).max));
    BaseTickBasedZapMigrateHook.BeforeExecutionData memory beforeData =
      BaseTickBasedZapMigrateHook.BeforeExecutionData({
        originalNftId: nftId,
        poolUniqueId: invalidPoolUniqueId,
        amount0Before: 1,
        amount1Before: 1,
        balance0Before: 0,
        balance1Before: 0,
        sqrtPriceX96Before: type(uint160).max,
        directionalPositionValue: 1,
        direction: true,
        additionalData: ''
      });

    vm.prank(address(router));
    vm.expectRevert(BaseTickBasedZapMigrateHook.InvalidPoolUniqueId.selector);
    zapHook.afterExecution(bytes32(0), intentData, abi.encode(beforeData), '');
  }

  function testFuzz_Revert_ExceedMaxValueReductionPerAction(ZapMigrateFuzzParams memory fuzz)
    public
  {
    uint256 nftId = PM.nextTokenId() - 1;
    PositionContext memory pos = _positionContext(nftId);
    address owner = PM.ownerOf(nftId);

    BaseTickBasedZapMigrateHook.ZapMigrateHookData memory hookData = _minimalHookData(nftId);
    hookData.maxValueReductionPerAction =
      bound(fuzz.maxValueReductionPerAction, 0, FEE_PRECISION - 1);
    uint256 directionalPositionValue = type(uint256).max - bound(fuzz.minValueInToken0, 0, 1e30);
    IntentData memory intentData = _buildIntentData(owner, hookData, nftId);

    BaseTickBasedZapMigrateHook.BeforeExecutionData memory beforeData =
      BaseTickBasedZapMigrateHook.BeforeExecutionData({
        originalNftId: nftId,
        poolUniqueId: pos.poolUniqueId,
        amount0Before: type(uint128).max,
        amount1Before: type(uint128).max,
        balance0Before: pos.token0.balanceOf(address(router)),
        balance1Before: pos.token1.balanceOf(address(router)),
        sqrtPriceX96Before: type(uint160).max,
        directionalPositionValue: directionalPositionValue,
        direction: true,
        additionalData: ''
      });

    vm.prank(address(router));
    vm.expectRevert(BaseTickBasedZapMigrateHook.ExceedMaxValueReductionPerAction.selector);
    zapHook.afterExecution(bytes32(0), intentData, abi.encode(beforeData), '');
  }

  function _actionParams(ZapMigrateFuzzParams memory fuzz, uint256 actionIndex)
    internal
    pure
    returns (uint256 amount0Desired, uint256 amount1Desired, uint24 actionFee0, uint24 actionFee1)
  {
    amount0Desired = bound(fuzz.actionAmount0Desireds[actionIndex], 0.1 ether, 5 ether);
    amount1Desired = bound(fuzz.actionAmount1Desireds[actionIndex], 100e6, 20_000e6);
    actionFee0 = uint24(bound(fuzz.actionFee0s[actionIndex], 0, 50_000));
    actionFee1 = uint24(bound(fuzz.actionFee1s[actionIndex], 0, 50_000));
  }

  function _prepareSuccessFirstMigration(
    ZapMigrateFuzzParams memory fuzz,
    uint256 oldNftId,
    PositionContext memory pos
  ) internal view returns (SuccessMigrationSetup memory setup) {
    uint24 actionFee00;
    uint24 actionFee10;
    (setup.amount0Desired0, setup.amount1Desired0, actionFee00, actionFee10) =
      _actionParams(fuzz, 0);
    (int24 newTickLower0, int24 newTickUpper0) = _newTicks(pos.currentTick, fuzz.newRangeMultiplier);

    BaseTickBasedZapMigrateHook.ZapMigrateHookData memory hookData =
      _successHookData(fuzz, oldNftId, pos, newTickLower0, newTickUpper0, actionFee00, actionFee10);
    hookData.maxDistanceFromLowerTickBeforeMigration = type(int24).max;
    hookData.maxDistanceFromUpperTickBeforeMigration = type(int24).max;

    setup.targetTickForSecondMigration =
      _clampInt24(fuzz.newTickAfterSwap, newTickLower0, newTickUpper0);

    (setup.amount0Desired1, setup.amount1Desired1, setup.actionFee01, setup.actionFee11) =
      _actionParams(fuzz, 1);
    int24 minRange = newTickUpper0 - newTickLower0;
    // Keep post-migration min-distance checks satisfiable for the second migration
    // regardless of tick alignment after swap and range reconstruction.
    hookData.minDistanceFromLowerTickAfterMigration =
      _clampInt24(fuzz.minDistanceFromLowerTickAfterMigration, 0, 1);
    hookData.minDistanceFromUpperTickAfterMigration =
      _clampInt24(fuzz.minDistanceFromUpperTickAfterMigration, 0, 1);
    hookData.minTickRangeLength = _clampInt24(fuzz.minTickRangeLength, 0, minRange);
    hookData.maxTickRangeLength = _clampInt24(fuzz.maxTickRangeLength, minRange, type(int24).max);
    uint256 actionFee0Max = actionFee00 > setup.actionFee01 ? actionFee00 : setup.actionFee01;
    uint256 actionFee1Max = actionFee10 > setup.actionFee11 ? actionFee10 : setup.actionFee11;
    hookData.maxFee0 = bound(fuzz.maxFee0, actionFee0Max, FEE_PRECISION);
    hookData.maxFee1 = bound(fuzz.maxFee1, actionFee1Max, FEE_PRECISION);

    setup.intentData = _buildIntentData(address(forwarder), hookData, oldNftId);
    setup.actionData0 = _buildActionData(
      oldNftId,
      newTickLower0,
      newTickUpper0,
      address(forwarder),
      setup.amount0Desired0,
      setup.amount1Desired0,
      actionFee00,
      actionFee10
    );
  }

  function _executeDelegated(IntentData memory intentData, ActionData memory actionData) internal {
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData, actionData);
    vm.prank(caller);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function _movePoolTickToTarget(
    uint256 nftId,
    PositionContext memory posBeforeSwap,
    int24 targetTick
  ) internal returns (PositionContext memory posAfterSwap) {
    _movePoolPriceToTick(posBeforeSwap.currentTick, targetTick);
    posAfterSwap = _positionContext(nftId);
  }

  function _movePoolPriceToTick(int24 currentTick, int24 targetTick) internal {
    if (targetTick == currentTick) return;
    bool zeroForOne = targetTick < currentTick;
    vm.deal(address(this), 1000 ether);
    deal(TOKEN1, address(this), type(uint128).max);
    vault.lock(abi.encode(SwapLockData({targetTick: targetTick, zeroForOne: zeroForOne})));
  }

  function lockAcquired(bytes calldata data) external returns (bytes memory) {
    return _onLockAcquired(data);
  }

  function lockCallback(bytes calldata data) external returns (bytes memory) {
    return _onLockAcquired(data);
  }

  function _onLockAcquired(bytes calldata data) internal returns (bytes memory) {
    require(msg.sender == address(vault), 'invalid vault');
    SwapLockData memory swapData = abi.decode(data, (SwapLockData));
    BalanceDelta delta = poolManager.swap(
      _poolKey(),
      ICLPoolManager.SwapParams({
        zeroForOne: swapData.zeroForOne,
        amountSpecified: -int256(type(int128).max),
        sqrtPriceLimitX96: TickMath.getSqrtRatioAtTick(swapData.targetTick)
      }),
      bytes('')
    );

    int128 amount0 = _amount0(delta);
    int128 amount1 = _amount1(delta);
    if (amount0 < 0) _settleCurrency(TOKEN0, uint128(-amount0));
    if (amount1 < 0) _settleCurrency(TOKEN1, uint128(-amount1));
    if (amount0 > 0) vault.take(TOKEN0, address(this), uint128(amount0));
    if (amount1 > 0) vault.take(TOKEN1, address(this), uint128(amount1));
    return bytes('');
  }

  function _settleCurrency(address currency, uint256 amount) internal {
    if (amount == 0) return;
    if (currency.isNative()) {
      vault.settle{value: amount}();
      return;
    }
    vault.sync(currency);
    currency.safeTransfer(address(vault), amount);
    vault.settle();
  }

  function _amount0(BalanceDelta delta) internal pure returns (int128 amount0) {
    assembly ('memory-safe') {
      amount0 := sar(128, delta)
    }
  }

  function _amount1(BalanceDelta delta) internal pure returns (int128 amount1) {
    amount1 = int128(uint128(uint256(BalanceDelta.unwrap(delta))));
  }

  function _successHookData(
    ZapMigrateFuzzParams memory fuzz,
    uint256 nftId,
    PositionContext memory pos,
    int24 newTickLower,
    int24 newTickUpper,
    uint24 actionFee0,
    uint24 actionFee1
  ) internal pure returns (BaseTickBasedZapMigrateHook.ZapMigrateHookData memory hookData) {
    int24 oldDistLower = pos.currentTick - pos.tickLower;
    int24 oldDistUpper = pos.tickUpper - pos.currentTick;
    int24 newDistLower = pos.currentTick - newTickLower;
    int24 newDistUpper = newTickUpper - pos.currentTick;
    int24 range = newTickUpper - newTickLower;

    hookData.nftId = nftId;
    hookData.minValueInToken0 = bound(fuzz.minValueInToken0, 0, 1);
    hookData.minValueInToken1 = bound(fuzz.minValueInToken1, 0, 1);
    hookData.maxValueReductionPerAction = FEE_PRECISION;
    hookData.maxDistanceFromLowerTickBeforeMigration =
      _clampInt24(fuzz.maxDistanceFromLowerTickBeforeMigration, oldDistLower, type(int24).max);
    hookData.maxDistanceFromUpperTickBeforeMigration =
      _clampInt24(fuzz.maxDistanceFromUpperTickBeforeMigration, oldDistUpper, type(int24).max);
    hookData.minDistanceFromLowerTickAfterMigration =
      _clampInt24(fuzz.minDistanceFromLowerTickAfterMigration, 0, newDistLower);
    hookData.minDistanceFromUpperTickAfterMigration =
      _clampInt24(fuzz.minDistanceFromUpperTickAfterMigration, 0, newDistUpper);
    hookData.minTickRangeLength = _clampInt24(fuzz.minTickRangeLength, 0, range);
    hookData.maxTickRangeLength = _clampInt24(fuzz.maxTickRangeLength, range, type(int24).max);
    hookData.maxFee0 = bound(fuzz.maxFee0, actionFee0, FEE_PRECISION);
    hookData.maxFee1 = bound(fuzz.maxFee1, actionFee1, FEE_PRECISION);
  }

  function _positionContext(uint256 nftId) internal view returns (PositionContext memory pos) {
    (PoolKey memory poolKey, int24 tickLower, int24 tickUpper,,,,) = PM.positions(nftId);
    pos.token0 = poolKey.currency0;
    pos.token1 = poolKey.currency1;
    pos.tickLower = tickLower;
    pos.tickUpper = tickUpper;
    pos.poolUniqueId = PoolId.unwrap(_toId(poolKey));
    (, pos.currentTick,,) = poolManager.getSlot0(_toId(poolKey));
  }

  function _newTicks(int24 currentTick, uint8 rangeMultiplier)
    internal
    pure
    returns (int24 lower, int24 upper)
  {
    uint8 m = uint8(_clamp(rangeMultiplier, 2, 120));
    if (m % 2 == 1) {
      m = m == 120 ? 119 : m + 1;
    }
    int24 base = currentTick / TICK_SPACING * TICK_SPACING;
    if (currentTick < 0 && currentTick % TICK_SPACING != 0) {
      base -= TICK_SPACING;
    }

    int24 range = int24(uint24(m)) * TICK_SPACING;
    lower = base - range / 2;
    upper = lower + range;

    if (upper <= currentTick) {
      upper += TICK_SPACING;
      lower += TICK_SPACING;
    }
    if (lower >= currentTick) {
      lower -= TICK_SPACING;
      upper -= TICK_SPACING;
    }
  }

  function _mintFreshPosition(
    address owner,
    uint8 mintRangeMultiplier,
    uint256 mintAmount0DesiredRaw,
    uint256 mintAmount1DesiredRaw
  ) internal returns (uint256 nftId, PositionContext memory pos) {
    PoolId poolId = _toId(_poolKey());
    (uint160 sqrtPriceX96, int24 currentTick,,) = poolManager.getSlot0(poolId);
    (int24 tickLower, int24 tickUpper) =
      _newTicks(currentTick, uint8(_clamp(mintRangeMultiplier, 40, 120)));

    uint256 mintAmount0Desired = bound(mintAmount0DesiredRaw, 0.5 ether, 3 ether);
    uint256 mintAmount1Desired = bound(mintAmount1DesiredRaw, 1000e6, 20_000e6);
    uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
      sqrtPriceX96,
      TickMath.getSqrtRatioAtTick(tickLower),
      TickMath.getSqrtRatioAtTick(tickUpper),
      mintAmount0Desired,
      mintAmount1Desired
    );

    address minter = address(this);
    vm.deal(minter, mintAmount0Desired + 1 ether);
    deal(TOKEN1, minter, mintAmount1Desired);
    TOKEN1.safeApprove(PERMIT2, 0);
    TOKEN1.safeApprove(PERMIT2, type(uint256).max);
    IAllowanceTransfer(PERMIT2).approve(TOKEN1, address(PM), type(uint160).max, type(uint48).max);

    bytes memory actions = new bytes(2);
    bytes[] memory params = new bytes[](2);
    actions[0] = bytes1(uint8(Actions.CL_MINT_POSITION));
    params[0] = abi.encode(
      _poolKey(),
      tickLower,
      tickUpper,
      uint256(liquidity),
      mintAmount0Desired,
      mintAmount1Desired,
      minter,
      bytes('')
    );
    actions[1] = bytes1(uint8(Actions.SETTLE_PAIR));
    params[1] = abi.encode(TOKEN0, TOKEN1);

    PM.modifyLiquidities{value: mintAmount0Desired}(abi.encode(actions, params), type(uint256).max);
    nftId = PM.nextTokenId() - 1;

    if (owner != minter) {
      PM.transferFrom(minter, owner, nftId);
    }

    vm.prank(owner);
    PM.approve(address(router), nftId);

    pos = _positionContext(nftId);
  }

  function _buildIntentData(
    address intentMainAddress,
    BaseTickBasedZapMigrateHook.ZapMigrateHookData memory hookData,
    uint256 nftId
  ) internal view returns (IntentData memory intentData) {
    IntentCoreData memory coreData = IntentCoreData({
      mainAddress: intentMainAddress,
      signatureVerifier: address(0),
      delegatedKey: delegatedPublicKey,
      actionContracts: [address(mockActionContract)].toMemoryArray(),
      actionSelectors: [MockActionContract.zapMigratePancakeV4.selector].toMemoryArray(),
      hook: address(zapHook),
      hookIntentData: abi.encode(hookData)
    });

    TokenData memory tokenData;
    tokenData.erc721Data = new ERC721Data[](1);
    tokenData.erc721Data[0] = ERC721Data({token: address(PM), tokenId: nftId, permitData: ''});

    intentData = IntentData({coreData: coreData, tokenData: tokenData, extraData: ''});
  }

  function _buildActionData(
    uint256 oldNftId,
    int24 newTickLower,
    int24 newTickUpper,
    address newNftRecipient,
    uint256 amount0Desired,
    uint256 amount1Desired,
    uint24 actionFee0,
    uint24 actionFee1
  ) internal view returns (ActionData memory actionData) {
    FeeInfo memory feeInfo;
    feeInfo.protocolRecipient = protocolRecipient;
    feeInfo.partnerFeeConfigs = new FeeConfig[][](2);
    feeInfo.partnerFeeConfigs[0] = new FeeConfig[](0);
    feeInfo.partnerFeeConfigs[1] = new FeeConfig[](0);

    MockActionContract.ZapMigratePancakeV4Params memory params =
      MockActionContract.ZapMigratePancakeV4Params({
        pm: PM,
        oldTokenId: oldNftId,
        newTickLower: newTickLower,
        newTickUpper: newTickUpper,
        router: address(router),
        mainAddress: newNftRecipient,
        amountDesireds: [amount0Desired, amount1Desired].toMemoryArray(),
        fees: [uint256(actionFee0), uint256(actionFee1)].toMemoryArray()
      });

    actionData = ActionData({
      erc20Ids: new uint256[](0),
      erc20Amounts: new uint256[](0),
      erc721Ids: [uint256(0)].toMemoryArray(),
      feeInfo: feeInfo,
      approvalFlags: type(uint256).max,
      actionSelectorId: 0,
      actionCalldata: abi.encode(params),
      hookActionData: '',
      extraData: '',
      deadline: block.timestamp + 1 days,
      nonce: 0
    });
  }

  function _minimalHookData(uint256 nftId)
    internal
    pure
    returns (BaseTickBasedZapMigrateHook.ZapMigrateHookData memory hookData)
  {
    hookData.nftId = nftId;
    hookData.maxDistanceFromLowerTickBeforeMigration = type(int24).max;
    hookData.maxDistanceFromUpperTickBeforeMigration = type(int24).max;
    hookData.minDistanceFromLowerTickAfterMigration = type(int24).min;
    hookData.minDistanceFromUpperTickAfterMigration = type(int24).min;
    hookData.maxTickRangeLength = type(int24).max;
    hookData.maxValueReductionPerAction = FEE_PRECISION;
    hookData.maxFee0 = FEE_PRECISION;
    hookData.maxFee1 = FEE_PRECISION;
  }

  function _poolKey() internal pure returns (PoolKey memory key) {
    key = PoolKey({
      currency0: TOKEN0,
      currency1: TOKEN1,
      hooks: POOL_HOOKS,
      poolManager: CL_POOL_MANAGER,
      fee: POOL_FEE,
      parameters: POOL_PARAMETERS
    });
  }

  function _toId(PoolKey memory key) internal pure returns (PoolId poolId) {
    assembly ('memory-safe') {
      poolId := keccak256(key, 0xc0)
    }
  }

  function _clamp(uint256 value, uint256 min, uint256 max) internal pure returns (uint256) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  function _clampInt24(int24 value, int24 min, int24 max) internal pure returns (int24) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  receive() external payable {}
}
