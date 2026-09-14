// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './ConditionalSwapBase.t.sol';

import {IMulticall3} from 'forge-std/interfaces/IMulticall3.sol';
import {IAccessControl} from 'openzeppelin-contracts/contracts/access/IAccessControl.sol';
import {IPullOracleBase} from 'pull-oracle-consumer/src/interfaces/IPullOracleBase.sol';
import {
  IPullOracleReferenceHooks
} from 'pull-oracle-consumer/src/interfaces/IPullOracleReferenceHooks.sol';
import {IOracleAdapter} from 'src/interfaces/oracle/IOracleAdapter.sol';
import {AtlasOracleAdapter} from 'src/oracle-adapter/AtlasOracleAdapter.sol';

contract AtlasOracleTest is ConditionalSwapBaseTest {
  using SafeERC20 for IERC20;
  using TokenHelper for address;
  using ArraysHelper for *;
  using MerkleUtils for *;

  // tokenIn = USDT (6 decimals), tokenOut = WBTC (8 decimals) on the mainnet fork.
  // Per-token USD prices, USD-per-whole-token scaled by 1e18:
  uint256 internal constant USDT_USD = 1e18; // $1
  uint256 internal constant BTC_USD = 100_000e18; // $100k
  // Derived swap ratio (amountOut_raw * 1e18 / amountIn_raw) for the mock prices: 1e15.
  uint256 internal constant ORACLE_RATIO = 1e15;
  // WBTC per whole USD/USDT, scaled by 1e18.
  uint256 internal constant WBTC_PER_USD = 1e13;
  uint256 internal constant WBTC_PER_USDT = WBTC_PER_USD;
  uint256 internal constant USDT_PER_WBTC = 100_000e18;
  uint256 internal constant REAL_ORACLE_MAX_STALENESS = 15 hours;

  address internal constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;

  AtlasOracleAdapter internal atlasAdapter;

  address internal atlasSigner;
  uint256 internal atlasSignerKey;

  /// @dev Atlas feed ids carrying the same prices as the Chainlink/Pyth mocks above.
  bytes4 internal constant ATLAS_USDT_USD = 0x00000010;
  bytes4 internal constant ATLAS_WBTC_USD = 0x00000011;
  bytes4 internal constant ATLAS_WBTC_USDT = 0x00000012;
  bytes4 internal constant ATLAS_UNKNOWN_FEED = 0x00000099;
  bytes2 internal constant ATLAS_MAGIC_MARKER = 0x7096;
  uint256 internal constant ATLAS_MAX_STALENESS = 5 minutes;
  // AtlasOracleAdapter defaults for payload timestamps.
  uint256 internal constant ATLAS_MAX_DELAY = 180;
  uint256 internal constant ATLAS_MAX_FUTURE_DRIFT = 60;

  function _selectFork() public virtual override {
    vm.createSelectFork('mainnet', 25_386_536);
  }

  function setUp() public virtual override {
    super.setUp();

    (atlasSigner, atlasSignerKey) = makeAddrAndKey('atlasSigner');
    address[] memory atlasSigners = new address[](1);
    atlasSigners[0] = atlasSigner;
    atlasAdapter = new AtlasOracleAdapter(admin, atlasSigners);
  }

  function _atlasLeg(bytes4 feedId, PackedU128 priceLimits)
    internal
    view
    returns (TokenOracle memory)
  {
    return _atlasLeg(feedId, priceLimits, false, ATLAS_MAX_STALENESS);
  }

  function _atlasLeg(bytes4 feedId, PackedU128 priceLimits, bool inverse)
    internal
    view
    returns (TokenOracle memory)
  {
    return _atlasLeg(feedId, priceLimits, inverse, ATLAS_MAX_STALENESS);
  }

  function _atlasLeg(bytes4 feedId, PackedU128 priceLimits, bool inverse, uint256 maxStaleness)
    internal
    view
    returns (TokenOracle memory)
  {
    return TokenOracle(
      toBoolAddress(inverse, address(atlasAdapter)),
      toOracleSource(maxStaleness, address(0)),
      priceLimits,
      abi.encode(feedId)
    );
  }

  /// @dev One package: feed id | 1e18 price (80 bits) | unix seconds (48 bits).
  function _atlasPackage(bytes4 feedId, uint256 price, uint256 timestamp)
    internal
    pure
    returns (bytes memory)
  {
    return abi.encodePacked(feedId, uint80(price), uint48(timestamp));
  }

  function _atlasPayload() internal view returns (bytes memory) {
    return _atlasPayload(atlasSignerKey, vm.getBlockTimestamp());
  }

  function _atlasPayload(uint256 timestamp) internal view returns (bytes memory) {
    return _atlasPayload(atlasSignerKey, timestamp);
  }

  function _atlasPayload(uint256 key, uint256 timestamp) internal pure returns (bytes memory) {
    bytes memory packages = bytes.concat(
      _atlasPackage(ATLAS_USDT_USD, USDT_USD, timestamp),
      _atlasPackage(ATLAS_WBTC_USD, BTC_USD, timestamp),
      _atlasPackage(ATLAS_WBTC_USDT, WBTC_PER_USDT, timestamp)
    );
    return _atlasSign(key, packages, 3);
  }

  /// @dev Mirrors the Atlas SDK extra data: packages | count | r | s | v | marker.
  function _atlasSign(uint256 key, bytes memory packages, uint8 count)
    internal
    pure
    returns (bytes memory)
  {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, keccak256(abi.encodePacked(packages, count)));
    return abi.encodePacked(packages, count, r, s, v, ATLAS_MAGIC_MARKER);
  }

  function _atlasFeedIds() internal pure returns (bytes4[] memory feedIds) {
    feedIds = new bytes4[](3);
    feedIds[0] = ATLAS_USDT_USD;
    feedIds[1] = ATLAS_WBTC_USD;
    feedIds[2] = ATLAS_WBTC_USDT;
  }

  function _atlasFeedIds(bytes4 feedId) internal pure returns (bytes4[] memory feedIds) {
    feedIds = new bytes4[](1);
    feedIds[0] = feedId;
  }

  function _atlasUpdateCall(bytes memory payload) internal pure returns (bytes memory) {
    return _atlasUpdateCall(_atlasFeedIds(), payload);
  }

  /// @dev `updatePrices(feedIds)` with the signed payload appended, as the Atlas SDK sends it.
  function _atlasUpdateCall(bytes4[] memory feedIds, bytes memory payload)
    internal
    pure
    returns (bytes memory)
  {
    return bytes.concat(abi.encodeCall(AtlasOracleAdapter.updatePrices, (feedIds)), payload);
  }

  function _pushAtlas(bytes memory updateCall) internal {
    (bool success, bytes memory returnData) = address(atlasAdapter).call(updateCall);
    if (!success) {
      assembly ('memory-safe') {
        revert(add(returnData, 0x20), mload(returnData))
      }
    }
  }

  function _expectAtlasUpdateRevert(bytes memory updateCall, bytes memory expected) internal {
    (bool success, bytes memory returnData) = address(atlasAdapter).call(updateCall);
    assertFalse(success);
    assertEq(returnData, expected);
  }

  /// @dev Push, wait `delay`, then read in one call, so the transient cache also survives `--isolate`.
  function pushAndReadAtlas(bytes calldata updateCall, uint256 delay, TokenOracle calldata leg)
    external
    returns (uint256)
  {
    _pushAtlas(updateCall);
    skip(delay);
    return atlasAdapter.getPrice(leg);
  }

  function _executeWithAtlasUpdateMulticall(
    uint256 mode,
    IntentData memory intentData,
    ActionData memory actionData,
    bytes memory payload,
    bool allowRouterFailure
  ) internal returns (IMulticall3.Result[] memory results) {
    (address caller,,) = _getCallerAndSignatures(mode, intentData, actionData);
    bytes memory dkSignature = _getDKSignature(intentData, actionData);
    bytes memory gdSignature = _getGDSignature(intentData, actionData);

    IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](2);
    calls[0] = IMulticall3.Call3Value({
      target: address(atlasAdapter),
      allowFailure: false,
      value: 0,
      callData: _atlasUpdateCall(payload)
    });
    calls[1] = IMulticall3.Call3Value({
      target: address(router),
      allowFailure: allowRouterFailure,
      value: 0,
      callData: abi.encodeCall(
        router.execute, (intentData, dkSignature, guardian, gdSignature, actionData)
      )
    });

    vm.startPrank(caller);
    results = IMulticall3(MULTICALL3).aggregate3Value(calls);
    vm.stopPrank();

    assertTrue(results[0].success);
    if (!allowRouterFailure) {
      assertTrue(results[1].success);
    }
  }

  function _expectAtlasSwapOk(uint256 mode, OracleConfig memory cfg, uint256 amountOut) internal {
    (IntentData memory intentData, ActionData memory actionData) =
      _buildIntentAndAction(_single(cfg), amountOut);

    uint256 balBefore = IERC20(tokenOut).balanceOf(mainAddress);
    _executeWithAtlasUpdateMulticall(mode, intentData, actionData, _atlasPayload(), false);
    assertGt(IERC20(tokenOut).balanceOf(mainAddress), balBefore);
  }

  function _expectAtlasSwapRevert(uint256 mode, OracleConfig memory cfg, uint256 amountOut)
    internal
  {
    (IntentData memory intentData, ActionData memory actionData) =
      _buildIntentAndAction(_single(cfg), amountOut);

    IMulticall3.Result[] memory results =
      _executeWithAtlasUpdateMulticall(mode, intentData, actionData, _atlasPayload(), true);
    assertFalse(results[1].success);
  }

  function test_Atlas_MarketTrigger_Pass(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleConfig memory cfg = _config(
      _atlasLeg(ATLAS_USDT_USD, _band(USDT_USD, 100, 100)),
      _atlasLeg(ATLAS_WBTC_USD, _band(WBTC_PER_USD, 100, 100), true),
      0
    );
    _expectAtlasSwapOk(mode, cfg, _amountOutFor(ORACLE_RATIO));
  }

  function test_Atlas_MarketTrigger_Revert(uint256 mode) public {
    mode = bound(mode, 0, 2);
    // tokenOut band sits entirely above the signed BTC price -> never met
    OracleConfig memory cfg = _config(
      _atlasLeg(ATLAS_USDT_USD, _band(USDT_USD, 100, 100)),
      _atlasLeg(ATLAS_WBTC_USD, toPackedU128(WBTC_PER_USD * 2, type(uint128).max), true),
      0
    );
    _expectAtlasSwapRevert(mode, cfg, _amountOutFor(ORACLE_RATIO));
  }

  function test_Atlas_SlippageGuard_Pass(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleConfig memory cfg = _config(
      _atlasLeg(ATLAS_USDT_USD, _fullBand()),
      _atlasLeg(ATLAS_WBTC_USD, _fullBand(), true),
      1e17 // 10% tolerance
    );
    _expectAtlasSwapOk(mode, cfg, _amountOutFor((ORACLE_RATIO * 105) / 100)); // +5%
  }

  function test_Atlas_SlippageGuard_MinRevert(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleConfig memory cfg = _config(
      _atlasLeg(ATLAS_USDT_USD, _fullBand()),
      _atlasLeg(ATLAS_WBTC_USD, _fullBand(), true),
      1e16 // 1% tolerance
    );
    _expectAtlasSwapRevert(mode, cfg, _amountOutFor((ORACLE_RATIO * 95) / 100)); // -5%
  }

  function test_Atlas_OracleRatioLimit_Pass(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleConfig memory cfg = _config(
      _atlasLeg(ATLAS_USDT_USD, _fullBand()),
      _atlasLeg(ATLAS_WBTC_USD, _fullBand(), true),
      0,
      _band(ORACLE_RATIO, 100, 100)
    );
    _expectAtlasSwapOk(mode, cfg, _amountOutFor(ORACLE_RATIO));
  }

  function test_Atlas_OracleRatioLimit_Revert(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleConfig memory cfg = _config(
      _atlasLeg(ATLAS_USDT_USD, _fullBand()),
      _atlasLeg(ATLAS_WBTC_USD, _fullBand(), true),
      0,
      toPackedU128(ORACLE_RATIO * 2, type(uint128).max)
    );
    _expectAtlasSwapRevert(mode, cfg, _amountOutFor(ORACLE_RATIO));
  }

  function test_Atlas_DirectPair_MarketTrigger_Pass(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleConfig memory cfg =
      _directConfig(_atlasLeg(ATLAS_WBTC_USDT, _band(WBTC_PER_USDT, 100, 100)), 1e16);
    _expectAtlasSwapOk(mode, cfg, _amountOutFor(ORACLE_RATIO));
  }

  function testRevert_Atlas_NoUpdateInTx(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleConfig memory cfg = _config(
      _atlasLeg(ATLAS_USDT_USD, _fullBand()), _atlasLeg(ATLAS_WBTC_USD, _fullBand(), true), 0
    );

    (IntentData memory intentData, ActionData memory actionData) =
      _buildIntentAndAction(_single(cfg), _amountOutFor(ORACLE_RATIO));
    _expectExecuteRevert(mode, intentData, actionData, IOracleAdapter.InvalidOraclePrice.selector);
  }

  function testRevert_Atlas_StalePrice(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleConfig memory cfg = _config(
      _atlasLeg(ATLAS_USDT_USD, _fullBand(), false, 60),
      _atlasLeg(ATLAS_WBTC_USD, _fullBand(), true, 60),
      0
    );

    (IntentData memory intentData, ActionData memory actionData) =
      _buildIntentAndAction(_single(cfg), _amountOutFor(ORACLE_RATIO));
    IMulticall3.Result[] memory results = _executeWithAtlasUpdateMulticall(
      mode, intentData, actionData, _atlasPayload(vm.getBlockTimestamp() - 61), true
    );
    assertFalse(results[1].success);
  }

  function testFuzz_Atlas_RoundTrip(uint80 price, uint256 age) public {
    price = uint80(bound(price, 1, type(uint80).max));
    age = bound(age, 0, ATLAS_MAX_DELAY);
    bytes memory payload = _atlasSign(
      atlasSignerKey, _atlasPackage(ATLAS_USDT_USD, price, vm.getBlockTimestamp() - age), 1
    );
    bytes memory updateCall = _atlasUpdateCall(_atlasFeedIds(ATLAS_USDT_USD), payload);

    assertEq(this.pushAndReadAtlas(updateCall, 0, _atlasLeg(ATLAS_USDT_USD, _fullBand())), price);
  }

  /// @dev the leg's own `maxStaleness`, checked by `getPrice` after a valid push
  function testRevert_Atlas_GetPrice_Stale() public {
    bytes memory updateCall = _atlasUpdateCall(_atlasPayload());
    TokenOracle memory leg = _atlasLeg(ATLAS_USDT_USD, _fullBand());

    vm.expectRevert(IOracleAdapter.StaleOraclePrice.selector);
    this.pushAndReadAtlas(updateCall, ATLAS_MAX_STALENESS + 1, leg);
  }

  function testRevert_Atlas_NoPayload() public {
    _expectAtlasUpdateRevert(
      _atlasUpdateCall(''), abi.encodeWithSelector(IPullOracleBase.InvalidMarker.selector)
    );
  }

  function testRevert_Atlas_UnauthorizedSigner() public {
    uint256 intruderKey = uint256(keccak256('atlasIntruder'));
    _expectAtlasUpdateRevert(
      _atlasUpdateCall(_atlasPayload(intruderKey, vm.getBlockTimestamp())),
      abi.encodeWithSelector(IPullOracleBase.UnauthorizedSigner.selector, vm.addr(intruderKey))
    );
  }

  function testRevert_Atlas_FeedNotInPayload() public {
    bytes4[] memory feedIds = new bytes4[](2);
    feedIds[0] = ATLAS_USDT_USD;
    feedIds[1] = ATLAS_UNKNOWN_FEED;
    _expectAtlasUpdateRevert(
      _atlasUpdateCall(feedIds, _atlasPayload()),
      abi.encodeWithSelector(IPullOracleBase.UnmatchedFeedID.selector, ATLAS_UNKNOWN_FEED)
    );
  }

  function testRevert_Atlas_Expired() public {
    uint256 expired = vm.getBlockTimestamp() - ATLAS_MAX_DELAY - 1;
    _expectAtlasUpdateRevert(
      _atlasUpdateCall(_atlasPayload(expired)),
      abi.encodeWithSelector(
        IPullOracleReferenceHooks.PriceFeedExpired.selector,
        ATLAS_USDT_USD,
        expired,
        vm.getBlockTimestamp()
      )
    );
  }

  function testRevert_Atlas_FutureDrift() public {
    uint256 future = vm.getBlockTimestamp() + ATLAS_MAX_FUTURE_DRIFT + 1;
    _expectAtlasUpdateRevert(
      _atlasUpdateCall(_atlasPayload(future)),
      abi.encodeWithSelector(
        IPullOracleReferenceHooks.PriceFeedFutureDrift.selector,
        ATLAS_USDT_USD,
        future,
        vm.getBlockTimestamp()
      )
    );
  }

  function test_Atlas_RotateSigner() public {
    (address newSigner, uint256 newSignerKey) = makeAddrAndKey('atlasSigner2');
    vm.startPrank(admin);
    atlasAdapter.setSignerStatus(newSigner, true);
    atlasAdapter.setSignerStatus(atlasSigner, false);
    vm.stopPrank();

    _pushAtlas(_atlasUpdateCall(_atlasPayload(newSignerKey, vm.getBlockTimestamp())));
    _expectAtlasUpdateRevert(
      _atlasUpdateCall(_atlasPayload()),
      abi.encodeWithSelector(IPullOracleBase.UnauthorizedSigner.selector, atlasSigner)
    );
  }

  /// @dev the constructor authorizes every signer in the array
  function test_Atlas_MultipleInitialSigners() public {
    (address secondSigner, uint256 secondSignerKey) = makeAddrAndKey('atlasSigner2');
    address[] memory signers = new address[](2);
    signers[0] = atlasSigner;
    signers[1] = secondSigner;
    atlasAdapter = new AtlasOracleAdapter(admin, signers);

    assertTrue(atlasAdapter.isAuthorizedSigner(atlasSigner));
    assertTrue(atlasAdapter.isAuthorizedSigner(secondSigner));

    _pushAtlas(_atlasUpdateCall(_atlasPayload()));
    _pushAtlas(_atlasUpdateCall(_atlasPayload(secondSignerKey, vm.getBlockTimestamp())));
  }

  /// @dev a 30 minute old price is rejected by default, accepted once the admin widens the window
  function test_Atlas_SetMaxDelay() public {
    uint256 timestamp = vm.getBlockTimestamp() - 30 minutes;
    bytes memory updateCall = _atlasUpdateCall(_atlasPayload(timestamp));
    _expectAtlasUpdateRevert(
      updateCall,
      abi.encodeWithSelector(
        IPullOracleReferenceHooks.PriceFeedExpired.selector,
        ATLAS_USDT_USD,
        timestamp,
        vm.getBlockTimestamp()
      )
    );

    vm.prank(admin);
    atlasAdapter.setMaxDelay(1 hours);

    TokenOracle memory leg = _atlasLeg(ATLAS_USDT_USD, _fullBand(), false, 1 hours);
    assertEq(this.pushAndReadAtlas(updateCall, 0, leg), USDT_USD);
  }

  function testRevert_Atlas_SetSignerStatus_NotAdmin() public {
    address intruder = makeAddr('atlasIntruder');
    vm.prank(intruder);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, intruder, bytes32(0)
      )
    );
    atlasAdapter.setSignerStatus(intruder, true);
  }
}
