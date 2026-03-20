// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../Base.t.sol';
import {IERC721} from 'openzeppelin-contracts/contracts/interfaces/IERC721.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import {BaseTickBasedZapMigrateHook} from 'src/hooks/base/BaseTickBasedZapMigrateHook.sol';
import {
  KSZapMigrateUniswapV3Hook as KSZapMigrateUniswapV4Hook
} from 'src/hooks/zap-migrate/KSZapMigrateUniswapV4Hook.sol';
import {IPoolManager} from 'src/interfaces/uniswapv4/IPoolManager.sol';
import {IPositionManager} from 'src/interfaces/uniswapv4/IPositionManager.sol';
import {Actions, PoolKey} from 'src/interfaces/uniswapv4/Types.sol';
import {LiquidityAmounts} from 'src/libraries/uniswapv4/LiquidityAmounts.sol';
import {StateLibrary} from 'src/libraries/uniswapv4/StateLibrary.sol';
import {TickMath} from 'src/libraries/uniswapv4/TickMath.sol';

import {ZapMigrateFuzzParams} from './ZapMigrateFuzzParams.sol';

interface IAllowanceTransfer {
  function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

contract ZapMigrateUniswapV4Test is BaseTest {
  using ArraysHelper for *;
  using StateLibrary for IPoolManager;

  IPositionManager internal constant PM =
    IPositionManager(0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e);
  address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

  int24 internal constant HALF_RANGE = 500;
  uint256 internal constant FEE_ONE = 1_000_000;
  uint256 internal constant HOOK_MAX_FEE_10PCT = 100_000;

  PoolKey internal poolKey;
  KSZapMigrateUniswapV4Hook internal hook;

  int24 internal currentTick;
  int24 internal tickSpacing;
  uint160 internal sqrtPriceX96;

  /// @dev Active start position + zap target (set by `_mintStartPosition`).
  uint256 internal posNftId;
  int24 internal posTickLower;
  int24 internal posTickUpper;
  uint128 internal posLiquidity;

  int24 internal newTickLower;
  int24 internal newTickUpper;
  int24 internal lowerTickDelta;
  int24 internal upperTickDelta;

  function _selectFork() public override {
    FORK_BLOCK = 22_937_800;
    vm.createSelectFork('mainnet', FORK_BLOCK);
  }

  function setUp() public override {
    super.setUp();

    hook = new KSZapMigrateUniswapV4Hook(_singleAddr(address(router)));

    vm.prank(admin);
    router.grantRole(ACTION_CONTRACT_ROLE, address(mockActionContract));

    poolKey = PoolKey({
      currency0: address(0), currency1: USDC, fee: 500, tickSpacing: 10, hooks: address(0)
    });
    tickSpacing = poolKey.tickSpacing;

    (sqrtPriceX96, currentTick,,) = PM.poolManager().getSlot0(_poolId(poolKey));

    vm.startPrank(mainAddress);
    IERC20(USDC).approve(PERMIT2, type(uint256).max);
    IAllowanceTransfer(PERMIT2).approve(USDC, address(PM), type(uint160).max, type(uint48).max);
    PM.setApprovalForAll(address(router), true);
    vm.stopPrank();

    // `zapMigrateUniswapV4` pulls to `mockActionContract` then settles via Permit2; same PM allowance as `mainAddress`.
    vm.startPrank(address(mockActionContract));
    IERC20(USDC).approve(PERMIT2, type(uint256).max);
    IAllowanceTransfer(PERMIT2).approve(USDC, address(PM), type(uint160).max, type(uint48).max);
    vm.stopPrank();
  }

  // --- helpers ----------------------------------------------------------------

  function _singleAddr(address a) private pure returns (address[] memory r) {
    r = new address[](1);
    r[0] = a;
  }

  function _floorTick(int24 tick, int24 spacing) internal pure returns (int24) {
    int24 c = tick / spacing;
    if (tick < 0 && tick % spacing != 0) c--;
    return c * spacing;
  }

  function _poolId(PoolKey memory key) internal pure returns (bytes32 id) {
    assembly ('memory-safe') {
      id := keccak256(key, 0xa0)
    }
  }

  function _tickRange(uint256 info) internal pure returns (int24 tl, int24 tu) {
    assembly ('memory-safe') {
      tl := signextend(2, shr(8, info))
      tu := signextend(2, shr(32, info))
    }
  }

  function _deadline() private view returns (uint256) {
    return block.timestamp + 1 days;
  }

  /// @dev `minDistanceFromLower/UpperTick` so `beforeExecution` does not revert `TooLargeDistanceFromTickBoundaries`.
  function _minDistForMigrateHook() internal view returns (int24 minL, int24 minU) {
    if (currentTick < posTickLower) {
      return (int24(2), int24(1));
    }
    if (currentTick > posTickUpper) {
      return (int24(1), int24(2));
    }
    int24 dL = currentTick - posTickLower;
    int24 dU = posTickUpper - currentTick;
    if (dL <= dU) {
      return (dL + 2, int24(1));
    }
    return (int24(1), dU + 2);
  }

  /// @dev Fuzzed start: in-range (near lower / near upper) or one-sided; pool tick stays near a boundary vs the minted range.
  function _mintStartPosition(uint256 raw) internal returns (uint256 id) {
    int24 maxA = _floorTick(TickMath.MAX_TICK, tickSpacing);
    int24 minA = _floorTick(TickMath.MIN_TICK, tickSpacing);
    int24 aligned = _floorTick(currentTick, tickSpacing);

    uint256 h1 = uint256(keccak256(abi.encode(raw, uint256(1))));
    uint256 h2 = uint256(keccak256(abi.encode(raw, uint256(2))));
    uint8 profile = uint8(bound(h1, 0, 3));
    int24 mintTL;
    int24 mintTU;

    for (uint256 t = 0; t < 4; t++) {
      uint8 p = uint8((uint256(profile) + t) % 4);
      if (p == 0) {
        uint256 steps = bound(h2, 1, 40);
        mintTL = aligned - int24(uint24(steps)) * tickSpacing;
        mintTU = mintTL + 2 * HALF_RANGE;
      } else if (p == 1) {
        uint256 steps = bound(h2 >> 32, 1, 40);
        mintTU = aligned + int24(uint24(steps)) * tickSpacing;
        mintTL = mintTU - 2 * HALF_RANGE;
      } else if (p == 2) {
        mintTU = aligned - 2 * tickSpacing;
        mintTL = mintTU - HALF_RANGE;
      } else {
        mintTL = aligned + 2 * tickSpacing;
        mintTU = mintTL + HALF_RANGE;
      }

      if (mintTL < minA) {
        mintTL = minA;
        mintTU = mintTL + 2 * HALF_RANGE;
      }
      if (mintTU > maxA) {
        mintTU = maxA;
        mintTL = mintTU - 2 * HALF_RANGE;
      }

      bool ok;
      if (p <= 1) {
        ok = (mintTL < currentTick && currentTick < mintTU);
      } else if (p == 2) {
        ok = (currentTick > mintTU);
      } else {
        ok = (currentTick < mintTL);
      }
      if (!ok) continue;

      if (p <= 1) {
        newTickLower = mintTL + tickSpacing;
        newTickUpper = mintTU + tickSpacing;
      } else if (p == 2) {
        newTickUpper = mintTU + tickSpacing;
        newTickLower = newTickUpper - HALF_RANGE;
      } else {
        int24 shiftedL = mintTL - tickSpacing;
        int24 shiftedU = shiftedL + HALF_RANGE;
        if (currentTick < shiftedL) {
          newTickLower = shiftedL;
          newTickUpper = shiftedU;
        } else {
          newTickLower = mintTL;
          newTickUpper = mintTU;
        }
      }

      bytes memory mintActions = new bytes(2);
      bytes[] memory mintParams = new bytes[](2);
      mintActions[0] = bytes1(uint8(Actions.MINT_POSITION));
      mintActions[1] = bytes1(uint8(Actions.SETTLE_PAIR));
      mintParams[1] = abi.encode(poolKey.currency0, poolKey.currency1);

      uint256 usdcAmt = 1000e6;
      uint256 ethAmt = 2 ether;
      deal(USDC, mainAddress, usdcAmt);
      vm.deal(mainAddress, mainAddress.balance + ethAmt);

      uint160 sqrtL = TickMath.getSqrtRatioAtTick(mintTL);
      uint160 sqrtU = TickMath.getSqrtRatioAtTick(mintTU);
      uint128 L;
      if (p == 2) {
        L = LiquidityAmounts.getLiquidityForAmount1(sqrtL, sqrtU, usdcAmt);
      } else if (p == 3) {
        L = LiquidityAmounts.getLiquidityForAmount0(sqrtL, sqrtU, ethAmt);
      } else {
        L = LiquidityAmounts.getLiquidityForAmounts(sqrtPriceX96, sqrtL, sqrtU, ethAmt, usdcAmt);
      }

      mintParams[0] = abi.encode(
        poolKey,
        mintTL,
        mintTU,
        uint256(L),
        type(uint128).max,
        type(uint128).max,
        mainAddress,
        bytes('')
      );

      vm.startPrank(mainAddress);
      if (p == 2) {
        PM.modifyLiquidities(abi.encode(mintActions, mintParams), _deadline());
      } else {
        PM.modifyLiquidities{value: ethAmt}(abi.encode(mintActions, mintParams), _deadline());
      }
      vm.stopPrank();

      id = PM.nextTokenId() - 1;
      posNftId = id;
      (, uint256 posInfo) = PM.getPoolAndPositionInfo(id);
      (posTickLower, posTickUpper) = _tickRange(posInfo);
      posLiquidity = PM.getPositionLiquidity(id);
      lowerTickDelta = newTickLower - currentTick;
      upperTickDelta = newTickUpper - currentTick;
      return id;
    }
    revert('no fuzz mint');
  }

  function _boundExecutionParams(ZapMigrateFuzzParams memory p)
    internal
    pure
    returns (ZapMigrateFuzzParams memory)
  {
    // currency0 = native ETH; currency1 = USDC (6 decimals)
    p.amountDesired0 = bound(p.amountDesired0, 2 ether, 100 ether);
    p.amountDesired1 = bound(p.amountDesired1, 100e6, 100e9);
    p.maxFee0 = bound(p.maxFee0, 0, 500_000);
    p.maxFee1 = bound(p.maxFee1, 0, 500_000);
    p.fee0Percent = bound(p.fee0Percent, 0, p.maxFee0);
    p.fee1Percent = bound(p.fee1Percent, 0, p.maxFee1);
    return p;
  }

  function _defaultMigrateParams() internal pure returns (ZapMigrateFuzzParams memory p) {
    p.amountDesired0 = 10 ether;
    p.amountDesired1 = 1e9;
    p.maxFee0 = HOOK_MAX_FEE_10PCT;
    p.maxFee1 = HOOK_MAX_FEE_10PCT;
  }

  function _hookData(
    uint256 nftId,
    int24 lowerDelta,
    int24 upperDelta,
    uint256 maxFee0,
    uint256 maxFee1,
    uint256 minV0,
    uint256 minV1,
    uint256 maxReduction,
    int24 minDistL,
    int24 minDistU
  ) internal pure returns (bytes memory) {
    uint256[] memory maxFees = new uint256[](2);
    maxFees[0] = maxFee0;
    maxFees[1] = maxFee1;
    return abi.encode(
      BaseTickBasedZapMigrateHook.ZapMigrateHookData({
        nftAddress: address(PM),
        nftId: nftId,
        minValueInToken0: minV0,
        minValueInToken1: minV1,
        maxValueReductionPerAction: maxReduction,
        minDistanceFromLowerTick: minDistL,
        minDistanceFromUpperTick: minDistU,
        lowerTickDelta: lowerDelta,
        upperTickDelta: upperDelta,
        maxFees: maxFees
      })
    );
  }

  function _hookDataStandard(uint256 nftId, int24 ld, int24 ud, uint256 max0, uint256 max1)
    internal
    view
    returns (bytes memory)
  {
    (int24 minL, int24 minU) = _minDistForMigrateHook();
    return _hookData(nftId, ld, ud, max0, max1, 0, 0, type(uint128).max, minL, minU);
  }

  function _buildIntent(uint256 nftId, bytes memory hookBytes)
    internal
    returns (IntentData memory intent)
  {
    address[] memory contracts = new address[](1);
    contracts[0] = address(mockActionContract);
    bytes4[] memory selectors = new bytes4[](1);
    selectors[0] = MockActionContract.zapMigrateUniswapV4.selector;

    intent = IntentData({
      coreData: IntentCoreData({
        mainAddress: mainAddress,
        signatureVerifier: address(0),
        delegatedKey: delegatedPublicKey,
        actionContracts: contracts,
        actionSelectors: selectors,
        hook: address(hook),
        hookIntentData: hookBytes
      }),
      tokenData: _erc721One(nftId),
      extraData: ''
    });
    vm.prank(mainAddress);
    router.delegate(intent);
  }

  function _erc721One(uint256 nftId) private pure returns (TokenData memory td) {
    td.erc721Data = new ERC721Data[](1);
    td.erc721Data[0] = ERC721Data({token: address(PM), tokenId: nftId, permitData: ''});
  }

  function _buildAction(
    uint256 nftId,
    int24 nl,
    int24 nu,
    address recipient,
    ZapMigrateFuzzParams memory p,
    uint128 newLiq
  ) internal returns (ActionData memory actionData) {
    // Pool is native ETH (currency0) / USDC (currency1); match `ZapMigrateFuzzParams` token0/token1 ordering.
    vm.deal(address(mockActionContract), p.amountDesired0);
    deal(USDC, address(mockActionContract), p.amountDesired1);

    uint256[] memory desired = new uint256[](2);
    desired[0] = p.amountDesired0;
    desired[1] = p.amountDesired1;
    uint256[] memory feePercents = new uint256[](2);
    feePercents[0] = p.fee0Percent;
    feePercents[1] = p.fee1Percent;

    MockActionContract.ZapMigrateUniswapV4Params memory params =
      MockActionContract.ZapMigrateUniswapV4Params({
        pm: PM,
        oldTokenId: nftId,
        newTickLower: nl,
        newTickUpper: nu,
        router: address(router),
        mainAddress: recipient,
        newLiquidity: newLiq,
        amountDesireds: desired,
        fees: feePercents
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
      deadline: _deadline(),
      nonce: 0
    });
  }

  function _execute(IntentData memory intent, ActionData memory action) internal {
    (, bytes memory dk, bytes memory gd) = _getCallerAndSignatures(0, intent, action);
    vm.prank(randomCaller);
    router.execute(intent, dk, guardian, gd, action);
  }

  function _executeExpectRevert(IntentData memory intent, ActionData memory action, bytes4 sel)
    internal
  {
    (, bytes memory dk, bytes memory gd) = _getCallerAndSignatures(0, intent, action);
    vm.prank(randomCaller);
    vm.expectRevert(sel);
    router.execute(intent, dk, guardian, gd, action);
  }

  // --- fuzz tests -------------------------------------------------------------

  function testFuzz_ZapMigrate_Success(uint256 seed, ZapMigrateFuzzParams memory p) public {
    p = _boundExecutionParams(p);
    _mintStartPosition(seed);

    IntentData memory intent = _buildIntent(
      posNftId, _hookDataStandard(posNftId, lowerTickDelta, upperTickDelta, p.maxFee0, p.maxFee1)
    );
    ActionData memory action = _buildAction(posNftId, newTickLower, newTickUpper, mainAddress, p, 0);

    uint256 nextBefore = PM.nextTokenId();
    _execute(intent, action);
    assertEq(PM.nextTokenId(), nextBefore + 1);

    uint256 newId = PM.nextTokenId() - 1;
    assertEq(IERC721(address(PM)).ownerOf(newId), mainAddress);
    assertEq(hook.nftIds(router.hashTypedIntentData(intent)), newId);

    (, uint256 info) = PM.getPoolAndPositionInfo(newId);
    (int24 nl, int24 nu) = _tickRange(info);
    assertEq(nl, newTickLower);
    assertEq(nu, newTickUpper);
  }

  function _extraInvalidLower(uint8 mult) internal view returns (int24 extra) {
    int24 width = newTickUpper - newTickLower;
    uint256 maxSteps = uint256(int256(width / tickSpacing));
    unchecked {
      if (maxSteps > 0) maxSteps--;
    }
    if (maxSteps < 1) maxSteps = 1;
    if (maxSteps > 50) maxSteps = 50;
    extra = int24(uint24(bound(uint256(mult), 1, maxSteps))) * tickSpacing;
  }

  function testFuzz_Revert_InvalidTickLower(uint256 seed, uint8 mult) public {
    _mintStartPosition(seed);
    int24 extra = _extraInvalidLower(mult);

    ZapMigrateFuzzParams memory migrateParams = _defaultMigrateParams();
    IntentData memory intent = _buildIntent(
      posNftId,
      _hookDataStandard(
        posNftId, lowerTickDelta, upperTickDelta, migrateParams.maxFee0, migrateParams.maxFee1
      )
    );
    ActionData memory action =
      _buildAction(posNftId, newTickLower + extra, newTickUpper, mainAddress, migrateParams, 0);
    _executeExpectRevert(intent, action, BaseTickBasedZapMigrateHook.InvalidTickLower.selector);
  }

  /// @dev Skew **down** the minted upper by one spacing vs hook-expected `newTickUpper` → `InvalidTickUpper`.
  function test_Revert_InvalidTickUpper(uint256 seed) public {
    _mintStartPosition(seed);

    ZapMigrateFuzzParams memory migrateParams = _defaultMigrateParams();
    IntentData memory intent = _buildIntent(
      posNftId,
      _hookDataStandard(
        posNftId, lowerTickDelta, upperTickDelta, migrateParams.maxFee0, migrateParams.maxFee1
      )
    );
    ActionData memory action = _buildAction(
      posNftId, newTickLower, newTickUpper - tickSpacing, mainAddress, migrateParams, 0
    );
    _executeExpectRevert(intent, action, BaseTickBasedZapMigrateHook.InvalidTickUpper.selector);
  }

  function testFuzz_Revert_ExceedMaxFeesPercent(uint256 seed, ZapMigrateFuzzParams memory p)
    public
  {
    _mintStartPosition(seed);
    uint128 tinyLiq = 1;

    p.maxFee0 = 0;
    p.maxFee1 = 0;
    p.amountDesired0 = bound(p.amountDesired0, 2 ether, 50 ether);
    p.amountDesired1 = bound(p.amountDesired1, 100e6, 50e9);
    p.fee0Percent = FEE_ONE;
    p.fee1Percent = FEE_ONE;

    IntentData memory intent =
      _buildIntent(posNftId, _hookDataStandard(posNftId, lowerTickDelta, upperTickDelta, 0, 0));
    ActionData memory action =
      _buildAction(posNftId, newTickLower, newTickUpper, mainAddress, p, tinyLiq);
    _executeExpectRevert(intent, action, BaseTickBasedZapMigrateHook.ExceedMaxFeesPercent.selector);
  }

  function testFuzz_Revert_ExceedMaxValueReductionPerAction(
    uint256 seed,
    uint256 tinyLiqRaw,
    uint256 amount0Raw,
    uint256 amount1Raw
  ) public {
    _mintStartPosition(seed);
    uint128 tinyLiq = uint128(bound(tinyLiqRaw, 1, 1000));

    ZapMigrateFuzzParams memory migrateParams;
    migrateParams.maxFee0 = HOOK_MAX_FEE_10PCT;
    migrateParams.maxFee1 = HOOK_MAX_FEE_10PCT;
    migrateParams.amountDesired0 = bound(amount0Raw, 2 ether, 50 ether);
    migrateParams.amountDesired1 = bound(amount1Raw, 100e6, 2000e6);

    (int24 minL, int24 minU) = _minDistForMigrateHook();
    IntentData memory intent = _buildIntent(
      posNftId,
      _hookData(
        posNftId,
        lowerTickDelta,
        upperTickDelta,
        HOOK_MAX_FEE_10PCT,
        HOOK_MAX_FEE_10PCT,
        0,
        0,
        0,
        minL,
        minU
      )
    );
    ActionData memory action =
      _buildAction(posNftId, newTickLower, newTickUpper, mainAddress, migrateParams, tinyLiq);
    _executeExpectRevert(
      intent, action, BaseTickBasedZapMigrateHook.ExceedMaxValueReductionPerAction.selector
    );
  }

  function testFuzz_Revert_InvalidOwner(uint256 seed, uint256 wrongSeed) public {
    _mintStartPosition(seed);
    uint256 x = bound(wrongSeed, 1, type(uint160).max);
    uint160 m = uint160(mainAddress);
    uint160 nx = uint160(x);
    if (nx == m) nx = m == type(uint160).max ? uint160(1) : m + 1;

    ZapMigrateFuzzParams memory migrateParams = _defaultMigrateParams();
    IntentData memory intent = _buildIntent(
      posNftId,
      _hookDataStandard(
        posNftId, lowerTickDelta, upperTickDelta, migrateParams.maxFee0, migrateParams.maxFee1
      )
    );
    ActionData memory action =
      _buildAction(posNftId, newTickLower, newTickUpper, address(nx), migrateParams, 0);
    _executeExpectRevert(intent, action, BaseTickBasedZapMigrateHook.InvalidOwner.selector);
  }

  function testFuzz_Revert_InsufficientPositionValue_minToken0(uint256 seed) public {
    _mintStartPosition(seed);
    (int24 minL, int24 minU) = _minDistForMigrateHook();
    ZapMigrateFuzzParams memory migrateParams = _defaultMigrateParams();
    IntentData memory intent = _buildIntent(
      posNftId,
      _hookData(
        posNftId,
        lowerTickDelta,
        upperTickDelta,
        HOOK_MAX_FEE_10PCT,
        HOOK_MAX_FEE_10PCT,
        type(uint256).max,
        0,
        type(uint128).max,
        minL,
        minU
      )
    );
    ActionData memory action =
      _buildAction(posNftId, newTickLower, newTickUpper, mainAddress, migrateParams, 0);
    _executeExpectRevert(
      intent, action, BaseTickBasedZapMigrateHook.InsufficientPositionValue.selector
    );
  }

  function testFuzz_Revert_InsufficientPositionValue_minToken1(uint256 seed) public {
    _mintStartPosition(seed);
    (int24 minL, int24 minU) = _minDistForMigrateHook();
    ZapMigrateFuzzParams memory migrateParams = _defaultMigrateParams();
    IntentData memory intent = _buildIntent(
      posNftId,
      _hookData(
        posNftId,
        lowerTickDelta,
        upperTickDelta,
        HOOK_MAX_FEE_10PCT,
        HOOK_MAX_FEE_10PCT,
        0,
        type(uint256).max,
        type(uint128).max,
        minL,
        minU
      )
    );
    ActionData memory action =
      _buildAction(posNftId, newTickLower, newTickUpper, mainAddress, migrateParams, 0);
    _executeExpectRevert(
      intent, action, BaseTickBasedZapMigrateHook.InsufficientPositionValue.selector
    );
  }
}
