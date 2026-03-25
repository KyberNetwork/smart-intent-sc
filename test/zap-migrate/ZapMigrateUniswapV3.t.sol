// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../Base.t.sol';

import 'src/hooks/base/BaseHook.sol';
import 'src/hooks/base/BaseTickBasedZapMigrateHook.sol';
import 'src/hooks/zap-migrate/KSZapMigrateUniswapV3Hook.sol';

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import 'src/interfaces/uniswapv3/IUniswapV3Factory.sol';
import 'src/interfaces/uniswapv3/IUniswapV3PM.sol';
import 'src/interfaces/uniswapv3/IUniswapV3Pool.sol';
import {TickMath} from 'src/libraries/uniswapv4/TickMath.sol';

import './ZapMigrateFuzzParams.sol';

contract ZapMigrateUniswapV3Test is BaseTest {
  using ArraysHelper for *;

  IUniswapV3PM internal constant PM = IUniswapV3PM(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
  IUniswapV3Pool internal constant POOL =
    IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
  address internal constant TOKEN0 = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
  address internal constant TOKEN1 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
  uint24 internal constant POOL_FEE = 500;

  int24 internal constant TICK_SPACING = 10;
  uint256 internal constant FEE_PRECISION = 1_000_000;

  KSZapMigrateUniswapV3Hook internal zapHook;

  struct PositionContext {
    address token0;
    address token1;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
    int24 currentTick;
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
    FORK_BLOCK = 22_230_873;
    vm.createSelectFork('mainnet', FORK_BLOCK);
  }

  function setUp() public override {
    super.setUp();
    zapHook = new KSZapMigrateUniswapV3Hook([address(router)].toMemoryArray());
  }

  function testFuzz_ZapMigrateUniswapV3_Success(ZapMigrateFuzzParams memory fuzz) public {
    (uint256 oldNftId, PositionContext memory pos) = _mintFreshPosition(
      address(forwarder), fuzz.mintRangeMultiplier, fuzz.mintAmount0Desired, fuzz.mintAmount1Desired
    );
    SuccessMigrationSetup memory setup = _prepareSuccessFirstMigration(fuzz, oldNftId, pos);

    deal(pos.token0, address(mockActionContract), setup.amount0Desired0);
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

    deal(posAfterSwap.token0, address(mockActionContract), setup.amount0Desired1);
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

    uint256 amount0Desired = bound(fuzz.actionAmount0Desireds[0], 1e9, 2000e6);
    uint256 amount1Desired = bound(fuzz.actionAmount1Desireds[0], 1e15, 2 ether);

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
    ActionData memory actionData =
      _buildActionData(oldNftId, newTickLower, newTickUpper, address(forwarder), 1e18, 1e18, 0, 0);

    vm.expectRevert(BaseTickBasedZapMigrateHook.TooLargeDistanceFromTickBoundaries.selector);
    vm.prank(address(router));
    zapHook.beforeExecution(bytes32(0), intentData, actionData);
  }

  function testFuzz_Revert_InvalidOwner(ZapMigrateFuzzParams memory fuzz) public {
    (uint256 oldNftId, PositionContext memory pos) = _mintFreshPosition(
      mainAddress, fuzz.mintRangeMultiplier, fuzz.mintAmount0Desired, fuzz.mintAmount1Desired
    );
    (int24 newTickLower, int24 newTickUpper) = _newTicks(pos.currentTick, fuzz.newRangeMultiplier);

    uint256 amount0Desired = bound(fuzz.actionAmount0Desireds[0], 1e9, 40_000e6);
    uint256 amount1Desired = bound(fuzz.actionAmount1Desireds[0], 1 ether, 30 ether);

    BaseTickBasedZapMigrateHook.ZapMigrateHookData memory hookData =
      _successHookData(fuzz, oldNftId, pos, newTickLower, newTickUpper, 0, 0);
    IntentData memory intentData = _buildIntentData(mainAddress, hookData, oldNftId);
    ActionData memory actionData = _buildActionData(
      oldNftId, newTickLower, newTickUpper, mainAddress, amount0Desired, amount1Desired, 0, 0
    );

    deal(pos.token0, address(mockActionContract), amount0Desired);
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

    uint256 amount0Desired = bound(fuzz.actionAmount0Desireds[0], 1e9, 40_000e6);
    uint256 amount1Desired = bound(fuzz.actionAmount1Desireds[0], 1 ether, 30 ether);
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

    deal(pos.token0, address(mockActionContract), amount0Desired);
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
    ActionData memory actionData =
      _buildActionData(oldNftId, newTickLower, newTickUpper, address(forwarder), 1e18, 1e18, 0, 0);

    deal(pos.token0, address(mockActionContract), 1e18);
    deal(pos.token1, address(mockActionContract), 1e18);

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
    ActionData memory actionData =
      _buildActionData(oldNftId, newTickLower, newTickUpper, address(forwarder), 1e18, 1e18, 0, 0);

    deal(pos.token0, address(mockActionContract), 1e18);
    deal(pos.token1, address(mockActionContract), 1e18);

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
    ActionData memory actionData =
      _buildActionData(oldNftId, newTickLower, newTickUpper, address(forwarder), 1e18, 1e18, 0, 0);

    deal(pos.token0, address(mockActionContract), 1e18);
    deal(pos.token1, address(mockActionContract), 1e18);

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
    ActionData memory actionData =
      _buildActionData(oldNftId, newTickLower, newTickUpper, address(forwarder), 1e18, 1e18, 0, 0);

    deal(pos.token0, address(mockActionContract), 1e18);
    deal(pos.token1, address(mockActionContract), 1e18);

    vm.prank(address(forwarder));
    router.delegate(intentData);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(0, intentData, actionData);

    vm.prank(caller);
    vm.expectRevert(BaseTickBasedZapMigrateHook.InsufficientPositionValue.selector);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function testFuzz_Revert_InvalidPoolUniqueId(ZapMigrateFuzzParams memory fuzz) public {
    (uint256 index, uint256 nftId, address owner,,, bytes32 poolUniqueId) =
      _samplePosition(fuzz.samplePositionIndex);

    BaseTickBasedZapMigrateHook.ZapMigrateHookData memory hookData = _minimalHookData(nftId);
    IntentData memory intentData = _buildIntentData(owner, hookData, nftId);

    bytes32 invalidPoolUniqueId =
      poolUniqueId ^ bytes32(_clamp(fuzz.invalidTokenErc20Amount, 1, type(uint256).max));
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
        additionalData: abi.encode(index)
      });

    vm.prank(address(router));
    vm.expectRevert(BaseTickBasedZapMigrateHook.InvalidPoolUniqueId.selector);
    zapHook.afterExecution(bytes32(0), intentData, abi.encode(beforeData), '');
  }

  function testFuzz_Revert_ExceedMaxValueReductionPerAction(ZapMigrateFuzzParams memory fuzz)
    public
  {
    (
      uint256 index,
      uint256 nftId,
      address owner,
      address token0,
      address token1,
      bytes32 poolUniqueId
    ) = _samplePosition(fuzz.samplePositionIndex);

    BaseTickBasedZapMigrateHook.ZapMigrateHookData memory hookData = _minimalHookData(nftId);
    hookData.maxValueReductionPerAction =
      bound(fuzz.maxValueReductionPerAction, 0, FEE_PRECISION - 1);
    uint256 directionalPositionValue = type(uint256).max - bound(fuzz.minValueInToken0, 0, 1e30);

    IntentData memory intentData = _buildIntentData(owner, hookData, nftId);

    BaseTickBasedZapMigrateHook.BeforeExecutionData memory beforeData =
      BaseTickBasedZapMigrateHook.BeforeExecutionData({
        originalNftId: nftId,
        poolUniqueId: poolUniqueId,
        amount0Before: type(uint128).max,
        amount1Before: type(uint128).max,
        balance0Before: IERC20(token0).balanceOf(address(router)),
        balance1Before: IERC20(token1).balanceOf(address(router)),
        sqrtPriceX96Before: type(uint160).max,
        directionalPositionValue: directionalPositionValue,
        direction: true,
        additionalData: abi.encode(index)
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
    amount0Desired = bound(fuzz.actionAmount0Desireds[actionIndex], 1e9, 40_000e6);
    amount1Desired = bound(fuzz.actionAmount1Desireds[actionIndex], 1 ether, 30 ether);
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

  function _currentTick() internal view returns (int24 tick) {
    (, tick,,,,,) = POOL.slot0();
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
    uint160 sqrtPriceLimitX96 = TickMath.getSqrtRatioAtTick(targetTick);

    deal(zeroForOne ? TOKEN0 : TOKEN1, address(this), type(uint128).max);

    POOL.swap(
      address(this),
      zeroForOne,
      int256(type(int128).max),
      sqrtPriceLimitX96,
      abi.encode(TOKEN0, TOKEN1)
    );
  }

  function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data)
    external
  {
    require(msg.sender == address(POOL), 'invalid pool caller');
    (address token0, address token1) = abi.decode(data, (address, address));
    if (amount0Delta > 0) {
      IERC20(token0).transfer(msg.sender, uint256(amount0Delta));
    }
    if (amount1Delta > 0) {
      IERC20(token1).transfer(msg.sender, uint256(amount1Delta));
    }
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
    (,, pos.token0, pos.token1, pos.fee, pos.tickLower, pos.tickUpper,,,,,) = PM.positions(nftId);
    (, pos.currentTick,,,,,) = POOL.slot0();
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
    (, int24 currentTick,,,,,) = POOL.slot0();
    (int24 tickLower, int24 tickUpper) =
      _newTicks(currentTick, uint8(_clamp(mintRangeMultiplier, 40, 120)));

    uint256 mintAmount0Desired = bound(mintAmount0DesiredRaw, 30_000e6, 40_000e6);
    uint256 mintAmount1Desired = bound(mintAmount1DesiredRaw, 18 ether, 22 ether);

    address minter = mainAddress;
    deal(TOKEN0, minter, mintAmount0Desired);
    deal(TOKEN1, minter, mintAmount1Desired);

    vm.startPrank(minter);
    IERC20(TOKEN0).approve(address(PM), type(uint256).max);
    IERC20(TOKEN1).approve(address(PM), type(uint256).max);
    (nftId,,,) = PM.mint(
      IUniswapV3PM.MintParams({
        token0: TOKEN0,
        token1: TOKEN1,
        fee: POOL_FEE,
        tickLower: tickLower,
        tickUpper: tickUpper,
        amount0Desired: mintAmount0Desired,
        amount1Desired: mintAmount1Desired,
        amount0Min: 0,
        amount1Min: 0,
        recipient: minter,
        deadline: block.timestamp + 1 days
      })
    );
    vm.stopPrank();

    if (owner != minter) {
      vm.prank(minter);
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
      actionSelectors: [MockActionContract.zapMigrateUniswapV3.selector].toMemoryArray(),
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

    MockActionContract.ZapMigrateUniswapV3Params memory params =
      MockActionContract.ZapMigrateUniswapV3Params({
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

  function _samplePosition(uint256 sampleIndex)
    internal
    view
    returns (
      uint256 index,
      uint256 nftId,
      address owner,
      address token0,
      address token1,
      bytes32 poolUniqueId
    )
  {
    uint256 total = PM.totalSupply();
    index = _clamp(sampleIndex, 0, total - 1);
    nftId = PM.tokenByIndex(index);
    owner = PM.ownerOf(nftId);
    uint24 fee;
    (,, token0, token1, fee,,,,,,,) = PM.positions(nftId);

    IUniswapV3Pool pool =
      IUniswapV3Pool(IUniswapV3Factory(PM.factory()).getPool(token0, token1, fee));
    poolUniqueId = bytes32(uint256(uint160(address(pool))));
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
}
