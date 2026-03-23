// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../Base.t.sol';
import {IERC721} from 'openzeppelin-contracts/contracts/interfaces/IERC721.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';

import {BaseTickBasedZapMigrateHook} from 'src/hooks/base/BaseTickBasedZapMigrateHook.sol';
import {KSZapMigrateUniswapV3Hook} from 'src/hooks/zap-migrate/KSZapMigrateUniswapV3Hook.sol';
import {IUniswapV3Factory} from 'src/interfaces/uniswapv3/IUniswapV3Factory.sol';
import {IUniswapV3PM} from 'src/interfaces/uniswapv3/IUniswapV3PM.sol';
import {IUniswapV3Pool} from 'src/interfaces/uniswapv3/IUniswapV3Pool.sol';
import {FixedPoint128} from 'src/libraries/uniswapv4/FixedPoint128.sol';
import {FixedPoint96} from 'src/libraries/uniswapv4/FixedPoint96.sol';
import {LiquidityAmounts} from 'src/libraries/uniswapv4/LiquidityAmounts.sol';
import {TickMath} from 'src/libraries/uniswapv4/TickMath.sol';

import {ZapMigrateFuzzParams} from './ZapMigrateFuzzParams.sol';

contract ZapMigrateUniswapV3Test is BaseTest {
  using ArraysHelper for *;
  using Math for uint256;

  IUniswapV3PM internal constant PM = IUniswapV3PM(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
  IUniswapV3Pool internal constant POOL =
    IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
  address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

  uint24 internal constant POOL_FEE = 500;
  int24 internal constant TICK_SPACING = 10;
  int24 internal constant HALF_RANGE = 500;

  uint256 internal constant FEE_ONE = 1_000_000;
  /// @dev Hook max-fee field (1e6 = 100%); safe with `maxValueReduction = type(uint128).max` (avoid uint256.max — hook adds it).
  uint256 internal constant HOOK_MAX_FEE_10PCT = 100_000;

  KSZapMigrateUniswapV3Hook internal hook;

  function _selectFork() public override {
    FORK_BLOCK = 22_230_873;
    vm.createSelectFork('mainnet', FORK_BLOCK);
  }

  function setUp() public override {
    super.setUp();

    hook = new KSZapMigrateUniswapV3Hook([address(router)].toMemoryArray());

    vm.prank(admin);
    router.grantRole(ACTION_CONTRACT_ROLE, address(mockActionContract));

    vm.startPrank(mainAddress);
    IERC20(USDC).approve(address(PM), type(uint256).max);
    IERC20(WETH).approve(address(PM), type(uint256).max);
    PM.setApprovalForAll(address(router), true);
    vm.stopPrank();
  }

  // --- helpers: setup & mint -------------------------------------------------

  function _floorTick(int24 tick, int24 spacing) internal pure returns (int24) {
    int24 c = tick / spacing;
    if (tick < 0 && tick % spacing != 0) c--;
    return c * spacing;
  }

  // --- helpers: position value (mirror hook) --------------------------------

  function _valueInToken0(uint256 sqrtPriceX96, uint256 amount0, uint256 amount1)
    internal
    pure
    returns (uint256)
  {
    return amount0
      + amount1.mulDiv(FixedPoint96.Q96, sqrtPriceX96).mulDiv(FixedPoint96.Q96, sqrtPriceX96);
  }

  function _valueInToken1(uint256 sqrtPriceX96, uint256 amount0, uint256 amount1)
    internal
    pure
    returns (uint256)
  {
    return amount1
      + amount0.mulDiv(sqrtPriceX96, FixedPoint96.Q96).mulDiv(sqrtPriceX96, FixedPoint96.Q96);
  }

  // --- helpers: fuzz bounds & hook/action build -------------------------------

  function _boundExecutionParams(ZapMigrateFuzzParams memory p)
    internal
    pure
    returns (ZapMigrateFuzzParams memory)
  {
    p.originalAmountDesired0 = bound(p.originalAmountDesired0, 1e6, 100e9);
    p.originalAmountDesired1 = bound(p.originalAmountDesired1, 1e15, 50 ether);
    p.newAmountDesired0 = bound(p.newAmountDesired0, 1e6, 100e9);
    p.newAmountDesired1 = bound(p.newAmountDesired1, 1e15, 50 ether);
    p.maxFee0 = bound(p.maxFee0, 0, 500_000);
    p.maxFee1 = bound(p.maxFee1, 0, 500_000);
    p.fee0Percent = bound(p.fee0Percent, 0, p.maxFee0);
    p.fee1Percent = bound(p.fee1Percent, 0, p.maxFee1);
    return p;
  }

  /// @dev Typical fixed params for revert tests that are not fuzzing amounts.
  function _defaultMigrateParams() internal pure returns (ZapMigrateFuzzParams memory p) {
    p.originalAmountDesired0 = 1e9;
    p.originalAmountDesired1 = 1e17;
    p.newAmountDesired0 = 1e9;
    p.newAmountDesired1 = 1e17;
    p.maxFee0 = HOOK_MAX_FEE_10PCT;
    p.maxFee1 = HOOK_MAX_FEE_10PCT;
  }

  function _hookData(
    uint256 maxFee0,
    uint256 maxFee1,
    uint256 minValueInToken0,
    uint256 minValueInToken1,
    uint256 maxValueReductionPerAction,
    int24 minDistLower,
    int24 minDistUpper
  ) internal pure returns (bytes memory) {
    uint256[] memory maxFees = new uint256[](2);
    maxFees[0] = maxFee0;
    maxFees[1] = maxFee1;
    return abi.encode(
      BaseTickBasedZapMigrateHook.ZapMigrateHookData({
        nftAddress: address(PM),
        minValueInToken0: minValueInToken0,
        minValueInToken1: minValueInToken1,
        maxValueReductionPerAction: maxValueReductionPerAction,
        minDistanceFromLowerTick: minDistLower,
        minDistanceFromUpperTick: minDistUpper,
        maxFees: maxFees
      })
    );
  }

  function _hookDataStandard(uint256 nftId, uint256 maxFee0, uint256 maxFee1)
    internal
    view
    returns (bytes memory)
  {
    (int24 minL, int24 minU) = _minDistForMigrateHookV3(nftId);
    return _hookData(maxFee0, maxFee1, 0, 0, type(uint128).max, minL, minU);
  }

  function _buildIntent(uint256 nftId, bytes memory hookData)
    internal
    returns (IntentData memory intentData)
  {
    address[] memory contracts = new address[](1);
    contracts[0] = address(mockActionContract);
    bytes4[] memory selectors = new bytes4[](1);
    selectors[0] = MockActionContract.zapMigrateUniswapV3.selector;

    intentData = IntentData({
      coreData: IntentCoreData({
        mainAddress: mainAddress,
        signatureVerifier: address(0),
        delegatedKey: delegatedPublicKey,
        actionContracts: contracts,
        actionSelectors: selectors,
        hook: address(hook),
        hookIntentData: hookData
      }),
      tokenData: _singleErc721(nftId),
      extraData: ''
    });
    vm.prank(mainAddress);
    router.delegate(intentData);
  }

  function _singleErc721(uint256 nftId) private pure returns (TokenData memory td) {
    td.erc721Data = new ERC721Data[](1);
    td.erc721Data[0] = ERC721Data({token: address(PM), tokenId: nftId, permitData: ''});
  }

  function _buildAction(
    uint256 nftId,
    int24 newLower,
    int24 newUpper,
    address mintRecipient,
    ZapMigrateFuzzParams memory p
  ) internal returns (ActionData memory actionData) {
    deal(USDC, address(mockActionContract), p.amountDesired0);
    deal(WETH, address(mockActionContract), p.amountDesired1);

    uint256[] memory desired = new uint256[](2);
    desired[0] = p.amountDesired0;
    desired[1] = p.amountDesired1;
    uint256[] memory fees = new uint256[](2);
    fees[0] = p.fee0Percent;
    fees[1] = p.fee1Percent;

    MockActionContract.ZapMigrateUniswapV3Params memory params =
      MockActionContract.ZapMigrateUniswapV3Params({
        pm: PM,
        oldTokenId: nftId,
        newTickLower: newLower,
        newTickUpper: newUpper,
        router: address(router),
        mainAddress: mintRecipient,
        amountDesireds: desired,
        fees: fees
      });

    FeeInfo memory feeInfo;
    feeInfo.protocolRecipient = protocolRecipient;
    feeInfo.partnerFeeConfigs = new FeeConfig[][](2);
    feeInfo.partnerFeeConfigs[0] = new FeeConfig[](0);
    feeInfo.partnerFeeConfigs[1] = new FeeConfig[](0);

    actionData = ActionData({
      erc20Ids: new uint256[](0),
      erc20Amounts: new uint256[](0),
      erc721Ids: [uint256(0)].toMemoryArray(),
      feeInfo: feeInfo,
      actionSelectorId: 0,
      approvalFlags: type(uint256).max,
      actionCalldata: abi.encode(params),
      hookActionData: '',
      extraData: '',
      deadline: _actionDeadline(),
      nonce: 0
    });
  }

  function _actionDeadline() private view returns (uint256) {
    return block.timestamp + 1 days;
  }

  function _execute(IntentData memory intentData, ActionData memory actionData) internal {
    (, bytes memory dk, bytes memory gd) = _getCallerAndSignatures(0, intentData, actionData);
    vm.prank(randomCaller);
    router.execute(intentData, dk, guardian, gd, actionData);
  }

  function _executeExpectRevert(
    IntentData memory intentData,
    ActionData memory actionData,
    bytes4 expectedSelector
  ) internal {
    (, bytes memory dk, bytes memory gd) = _getCallerAndSignatures(0, intentData, actionData);
    vm.prank(randomCaller);
    vm.expectRevert(expectedSelector);
    router.execute(intentData, dk, guardian, gd, actionData);
  }

  // --- fuzz tests -------------------------------------------------------------

  function testFuzz_ZapMigrate_Success(uint256 seed, ZapMigrateFuzzParams memory p) public {
    p = _boundExecutionParams(p);
    uint256 tokenId = _mintStartPosition(seed);

    IntentData memory intent =
      _buildIntent(tokenId, _hookDataStandard(tokenId, p.maxFee0, p.maxFee1));
    ActionData memory action = _buildAction(tokenId, newTickLower, newTickUpper, mainAddress, p);

    uint256 supplyBefore = PM.totalSupply();
    _execute(intent, action);

    assertEq(PM.totalSupply(), supplyBefore + 1, 'new NFT');
    uint256 newId = PM.tokenByIndex(PM.totalSupply() - 1);
    assertEq(IERC721(address(PM)).ownerOf(newId), mainAddress);
    assertEq(hook.nftIds(router.hashTypedIntentData(intent)), newId);

    (,,,,, int24 nl, int24 nu,,,,,) = PM.positions(newId);
    assertEq(nl, newTickLower);
    assertEq(nu, newTickUpper);
  }

  function testFuzz_Revert_TooLargeDistanceFromTickBoundaries(ZapMigrateFuzzParams memory p)
    public
  {
    p = _boundExecutionParams(p);

    deal(USDC, mainAddress, p.amountDesired0);
    deal(WETH, mainAddress, p.amountDesired1);
    vm.startPrank(mainAddress);
    (uint256 inRangeId,,,) = PM.mint(
      IUniswapV3PM.MintParams({
        token0: USDC,
        token1: WETH,
        fee: POOL_FEE,
        tickLower: _floorTick(currentTick, TICK_SPACING) - HALF_RANGE,
        tickUpper: _floorTick(currentTick, TICK_SPACING) + HALF_RANGE,
        amount0Desired: p.amountDesired0,
        amount1Desired: p.amountDesired1,
        amount0Min: 0,
        amount1Min: 0,
        recipient: mainAddress,
        deadline: _actionDeadline()
      })
    );
    vm.stopPrank();

    int24 aligned = _floorTick(currentTick, TICK_SPACING);
    int24 ntl = aligned - HALF_RANGE + TICK_SPACING;
    int24 ntu = aligned + HALF_RANGE + TICK_SPACING;

    IntentData memory intent =
      _buildIntent(inRangeId, _hookData(p.maxFee0, p.maxFee1, 0, 0, type(uint128).max, 0, 0));
    ActionData memory action = _buildAction(inRangeId, ntl, ntu, mainAddress, p);
    _executeExpectRevert(
      intent, action, BaseTickBasedZapMigrateHook.TooLargeDistanceFromTickBoundaries.selector
    );
  }

  function testFuzz_Revert_InsufficientPositionValue_Token0(uint256 seed, uint256 minValueBump)
    public
  {
    uint256 tokenId = _mintStartPosition(seed);
    minValueBump = bound(minValueBump, 1, type(uint128).max);
    (uint256 v0,) = _positionValues(tokenId);
    uint256 min0;
    unchecked {
      min0 = v0 + minValueBump;
    }

    ZapMigrateFuzzParams memory migrateParams = _defaultMigrateParams();
    (int24 minL, int24 minU) = _minDistForMigrateHookV3(tokenId);
    IntentData memory intent = _buildIntent(
      tokenId,
      _hookData(HOOK_MAX_FEE_10PCT, HOOK_MAX_FEE_10PCT, min0, 0, type(uint128).max, minL, minU)
    );
    ActionData memory action =
      _buildAction(tokenId, newTickLower, newTickUpper, mainAddress, migrateParams);
    _executeExpectRevert(
      intent, action, BaseTickBasedZapMigrateHook.InsufficientPositionValue.selector
    );
  }

  function testFuzz_Revert_InsufficientPositionValue_Token1(uint256 seed, uint256 minValueBump)
    public
  {
    uint256 tokenId = _mintStartPosition(seed);
    minValueBump = bound(minValueBump, 1, type(uint128).max);
    (, uint256 v1) = _positionValues(tokenId);
    uint256 min1;
    unchecked {
      min1 = v1 + minValueBump;
    }

    ZapMigrateFuzzParams memory migrateParams = _defaultMigrateParams();
    (int24 minL, int24 minU) = _minDistForMigrateHookV3(tokenId);
    IntentData memory intent = _buildIntent(
      tokenId,
      _hookData(HOOK_MAX_FEE_10PCT, HOOK_MAX_FEE_10PCT, 0, min1, type(uint128).max, minL, minU)
    );
    ActionData memory action =
      _buildAction(tokenId, newTickLower, newTickUpper, mainAddress, migrateParams);
    _executeExpectRevert(
      intent, action, BaseTickBasedZapMigrateHook.InsufficientPositionValue.selector
    );
  }

  function testFuzz_Revert_TooSmallDistance_InvalidTickLower(uint256 seed, uint8 spacingMult)
    public
  {
    uint256 tokenId = _mintStartPosition(seed);
    int24 maxBump = newTickUpper - newTickLower - int24(2) * TICK_SPACING;
    vm.assume(maxBump > TICK_SPACING);
    int24 extra = maxBump - int24(uint24(bound(uint256(spacingMult), 1, 40))) * TICK_SPACING;
    vm.assume(extra > int24(0));
    vm.assume(currentTick < newTickLower + extra + int24(1));
    vm.assume(newTickLower + extra < newTickUpper - TICK_SPACING);

    ZapMigrateFuzzParams memory migrateParams = _defaultMigrateParams();
    IntentData memory intent = _buildIntent(
      tokenId, _hookDataStandard(tokenId, migrateParams.maxFee0, migrateParams.maxFee1)
    );
    ActionData memory action =
      _buildAction(tokenId, newTickLower + extra, newTickUpper, mainAddress, migrateParams);
    _executeExpectRevert(
      intent, action, BaseTickBasedZapMigrateHook.TooSmallDistanceFromTickBoundaries.selector
    );
  }

  /// @dev Shrink upper tick (vs successful migrate) so pool tick is above `tickUpper - minDistance`.
  function testFuzz_Revert_TooSmallDistance_InvalidTickUpper(uint256 seed, uint8 spacingMult)
    public
  {
    uint256 tokenId = _mintStartPosition(seed);
    int24 extra = int24(uint24(bound(uint256(spacingMult), 1, 50))) * TICK_SPACING;

    ZapMigrateFuzzParams memory migrateParams = _defaultMigrateParams();
    IntentData memory intent = _buildIntent(
      tokenId, _hookDataStandard(tokenId, migrateParams.maxFee0, migrateParams.maxFee1)
    );
    ActionData memory action =
      _buildAction(tokenId, newTickLower, newTickUpper - extra, mainAddress, migrateParams);
    _executeExpectRevert(
      intent, action, BaseTickBasedZapMigrateHook.TooSmallDistanceFromTickBoundaries.selector
    );
  }

  function testFuzz_Revert_ExceedMaxFeesPercent(uint256 seed, ZapMigrateFuzzParams memory p)
    public
  {
    uint256 tokenId = _mintStartPosition(seed);

    p.maxFee0 = 0;
    p.maxFee1 = 0;
    p.amountDesired0 = bound(p.amountDesired0, 1e6, 50e6);
    p.amountDesired1 = bound(p.amountDesired1, 1e15, 5e17);
    // Both 100%: one-sided positions only have one token at collect; fee1=0 would skip WETH-only (profile 2).
    p.fee0Percent = FEE_ONE;
    p.fee1Percent = FEE_ONE;

    IntentData memory intent =
      _buildIntent(tokenId, _hookDataStandard(tokenId, p.maxFee0, p.maxFee1));
    ActionData memory action = _buildAction(tokenId, newTickLower, newTickUpper, mainAddress, p);
    _executeExpectRevert(intent, action, BaseTickBasedZapMigrateHook.ExceedMaxFeesPercent.selector);
  }

  function testFuzz_Revert_ExceedMaxValueReductionPerAction(
    uint256 seed,
    uint256 amount0Raw,
    uint256 amount1Raw
  ) public {
    uint256 tokenId = _mintStartPosition(seed);

    ZapMigrateFuzzParams memory migrateParams;
    migrateParams.maxFee0 = HOOK_MAX_FEE_10PCT;
    migrateParams.maxFee1 = HOOK_MAX_FEE_10PCT;
    migrateParams.amountDesired0 = bound(amount0Raw, 100e6, 2000e6);
    migrateParams.amountDesired1 = bound(amount1Raw, 1e14, 5e17);

    (int24 minL, int24 minU) = _minDistForMigrateHookV3(tokenId);
    IntentData memory intent =
      _buildIntent(tokenId, _hookData(HOOK_MAX_FEE_10PCT, HOOK_MAX_FEE_10PCT, 0, 0, 0, minL, minU));
    ActionData memory action =
      _buildAction(tokenId, newTickLower, newTickUpper, mainAddress, migrateParams);
    _executeExpectRevert(
      intent, action, BaseTickBasedZapMigrateHook.ExceedMaxValueReductionPerAction.selector
    );
  }

  function testFuzz_Revert_InvalidOwner(uint256 seed, uint256 wrongRecipientSeed) public {
    uint256 tokenId = _mintStartPosition(seed);

    uint256 x = bound(wrongRecipientSeed, 1, type(uint160).max);
    uint160 main = uint160(mainAddress);
    uint160 nx = uint160(x);
    if (nx == main) {
      nx = main == type(uint160).max ? uint160(1) : main + 1;
    }
    address wrongRecipient = address(nx);

    ZapMigrateFuzzParams memory migrateParams = _defaultMigrateParams();
    IntentData memory intent = _buildIntent(
      tokenId, _hookDataStandard(tokenId, migrateParams.maxFee0, migrateParams.maxFee1)
    );
    ActionData memory action =
      _buildAction(tokenId, newTickLower, newTickUpper, wrongRecipient, migrateParams);
    _executeExpectRevert(intent, action, BaseTickBasedZapMigrateHook.InvalidOwner.selector);
  }
}
