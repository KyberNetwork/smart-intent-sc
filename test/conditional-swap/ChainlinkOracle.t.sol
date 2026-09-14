// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './ConditionalSwapBase.t.sol';

import {ChainlinkOracleAdapter} from 'src/oracle-adapter/ChainlinkOracleAdapter.sol';
import {MockChainlinkFeed} from 'test/mocks/MockChainlinkFeed.sol';

contract ChainlinkOracleTest is ConditionalSwapBaseTest {
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

  // --- Real mainnet Chainlink aggregators ---
  address internal constant CHAINLINK_USDT_USD = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
  // WBTC tracks BTC; use the canonical BTC/USD aggregator for the WBTC leg.
  address internal constant CHAINLINK_WBTC_USD = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;

  MockChainlinkFeed internal feedIn;
  MockChainlinkFeed internal feedOut;
  MockChainlinkFeed internal feedDirect;
  MockChainlinkFeed internal feedDirectInverse;
  ChainlinkOracleAdapter internal chainlinkAdapter;

  function _selectFork() public virtual override {
    vm.createSelectFork('mainnet', 25_386_536);
  }

  function setUp() public virtual override {
    super.setUp();

    chainlinkAdapter = new ChainlinkOracleAdapter();

    feedIn = new MockChainlinkFeed(8, 1e8); // USDT/USD = $1
    feedOut = new MockChainlinkFeed(8, int256(100_000e8)); // WBTC/USD = $100k
    feedDirect = new MockChainlinkFeed(8, 1000); // WBTC/USDT = 0.00001
    feedDirectInverse = new MockChainlinkFeed(8, int256(USDT_PER_WBTC / 1e10)); // USDT/WBTC
  }

  /// @dev Mock Chainlink feeds report `block.timestamp`, so legs default to a zero staleness bound.
  function _chainlinkLeg(address feed, PackedU128 priceLimits)
    internal
    view
    returns (TokenOracle memory)
  {
    return _chainlinkLeg(feed, priceLimits, false, 0);
  }

  function _chainlinkLeg(address feed, PackedU128 priceLimits, bool inverse)
    internal
    view
    returns (TokenOracle memory)
  {
    return _chainlinkLeg(feed, priceLimits, inverse, 0);
  }

  function _chainlinkLeg(address feed, PackedU128 priceLimits, bool inverse, uint256 maxStaleness)
    internal
    view
    returns (TokenOracle memory)
  {
    return TokenOracle(
      toBoolAddress(inverse, address(chainlinkAdapter)),
      toOracleSource(maxStaleness, feed),
      priceLimits,
      abi.encode(bytes32(0))
    );
  }

  function _realChainlink(PackedU128 bandIn, PackedU128 bandOut)
    internal
    view
    returns (OracleConfig memory)
  {
    return _config(
      _chainlinkLeg(CHAINLINK_USDT_USD, bandIn, false, REAL_ORACLE_MAX_STALENESS),
      _chainlinkLeg(CHAINLINK_WBTC_USD, bandOut, true, REAL_ORACLE_MAX_STALENESS),
      0
    );
  }

  function test_Chainlink_MarketTrigger_Pass(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleConfig memory cfg = _config(
      _chainlinkLeg(address(feedIn), _band(USDT_USD, 100, 100)),
      _chainlinkLeg(address(feedOut), _band(WBTC_PER_USD, 100, 100), true),
      0
    );
    _expectSwapOk(mode, cfg, _amountOutFor(ORACLE_RATIO));
  }

  function test_Chainlink_MarketTrigger_Revert(uint256 mode) public {
    mode = bound(mode, 0, 2);
    // tokenOut band sits entirely above the live BTC price -> never met
    OracleConfig memory cfg = _config(
      _chainlinkLeg(address(feedIn), _band(USDT_USD, 100, 100)),
      _chainlinkLeg(address(feedOut), toPackedU128(WBTC_PER_USD * 2, type(uint128).max), true),
      0
    );
    _expectSwapRevert(mode, cfg, _amountOutFor(ORACLE_RATIO));
  }

  function test_Chainlink_SlippageGuard_Pass(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleConfig memory cfg = _config(
      _chainlinkLeg(address(feedIn), _fullBand()),
      _chainlinkLeg(address(feedOut), _fullBand(), true),
      1e17 // 10% tolerance
    );
    _expectSwapOk(mode, cfg, _amountOutFor((ORACLE_RATIO * 105) / 100)); // +5%
  }

  function test_Chainlink_SlippageGuard_MinRevert(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleConfig memory cfg = _config(
      _chainlinkLeg(address(feedIn), _fullBand()),
      _chainlinkLeg(address(feedOut), _fullBand(), true),
      1e16 // 1% tolerance
    );
    _expectSwapRevert(mode, cfg, _amountOutFor((ORACLE_RATIO * 95) / 100)); // -5%
  }

  function test_Chainlink_OracleRatioLimit_Pass(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleConfig memory cfg = _config(
      _chainlinkLeg(address(feedIn), _fullBand()),
      _chainlinkLeg(address(feedOut), _fullBand(), true),
      0,
      _band(ORACLE_RATIO, 100, 100)
    );
    _expectSwapOk(mode, cfg, _amountOutFor(ORACLE_RATIO));
  }

  function test_Chainlink_OracleRatioLimit_Revert(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleConfig memory cfg = _config(
      _chainlinkLeg(address(feedIn), _fullBand()),
      _chainlinkLeg(address(feedOut), _fullBand(), true),
      0,
      toPackedU128(ORACLE_RATIO * 2, type(uint128).max)
    );
    _expectSwapRevert(mode, cfg, _amountOutFor(ORACLE_RATIO));
  }

  function testRevert_Chainlink_SlippageGuard_InvalidMaxDeviation(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleConfig memory cfg = _config(
      _chainlinkLeg(address(feedIn), _fullBand()),
      _chainlinkLeg(address(feedOut), _fullBand(), true),
      1e18 + 1
    );

    (IntentData memory intentData, ActionData memory actionData) =
      _buildIntentAndAction(_single(cfg), _amountOutFor(ORACLE_RATIO));
    _expectExecuteRevert(mode, intentData, actionData, OracleLib.InvalidMaxDeviation.selector);
  }

  function test_Chainlink_DirectPair_OutSlotInverse_Pass(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleConfig memory cfg = _config(
      _emptyLeg(),
      _chainlinkLeg(address(feedDirectInverse), _band(WBTC_PER_USDT, 100, 100), true),
      1e16
    );
    _expectSwapOk(mode, cfg, _amountOutFor(ORACLE_RATIO));
  }

  function test_Chainlink_DirectPair_MarketTrigger_Pass(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleConfig memory cfg =
      _directConfig(_chainlinkLeg(address(feedDirect), _band(WBTC_PER_USDT, 100, 100)), 0);
    _expectSwapOk(mode, cfg, _amountOutFor(ORACLE_RATIO));
  }

  function test_Chainlink_DirectPair_MarketTrigger_Revert(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleConfig memory cfg = _directConfig(
      _chainlinkLeg(address(feedDirect), toPackedU128(WBTC_PER_USDT * 2, type(uint128).max)), 0
    );
    _expectSwapRevert(mode, cfg, _amountOutFor(ORACLE_RATIO));
  }

  function test_Chainlink_DirectPair_SlippageGuard_Pass(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleConfig memory cfg = _directConfig(
      _chainlinkLeg(address(feedDirect), _fullBand()),
      1e17 // 10% tolerance
    );
    _expectSwapOk(mode, cfg, _amountOutFor((ORACLE_RATIO * 105) / 100)); // +5%
  }

  function test_Chainlink_DirectPair_SlippageGuard_MinRevert(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleConfig memory cfg = _directConfig(
      _chainlinkLeg(address(feedDirect), _fullBand()),
      1e16 // 1% tolerance
    );
    _expectSwapRevert(mode, cfg, _amountOutFor((ORACLE_RATIO * 95) / 100)); // -5%
  }

  function test_Chainlink_DirectPair_Inverse_Pass(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleConfig memory cfg = _directConfig(
      _chainlinkLeg(address(feedDirectInverse), _band(WBTC_PER_USDT, 100, 100), true), 1e16
    );
    _expectSwapOk(mode, cfg, _amountOutFor(ORACLE_RATIO));
  }

  function test_Fork_ChainlinkReal_MarketTrigger_Pass(uint256 mode) public {
    mode = bound(mode, 0, 2);
    (uint256 priceIn, uint256 priceOut, uint256 ratio) =
      _readReal(_realChainlink(_fullBand(), _fullBand()));

    OracleConfig memory cfg = _realChainlink(_band(priceIn, 100, 100), _band(priceOut, 100, 100));
    _expectSwapOk(mode, cfg, _amountOutFor(ratio));
  }

  function test_Fork_ChainlinkReal_MarketTrigger_Revert(uint256 mode) public {
    mode = bound(mode, 0, 2);
    (, uint256 priceOut, uint256 ratio) = _readReal(_realChainlink(_fullBand(), _fullBand()));

    OracleConfig memory cfg =
      _realChainlink(_fullBand(), toPackedU128(priceOut * 2, type(uint128).max));
    _expectSwapRevert(mode, cfg, _amountOutFor(ratio));
  }

  function test_Fork_ChainlinkReal_SlippageGuard_Revert(uint256 mode) public {
    mode = bound(mode, 0, 2);
    (,, uint256 ratio) = _readReal(_realChainlink(_fullBand(), _fullBand()));

    OracleConfig memory cfg = _realChainlink(_fullBand(), _fullBand());
    cfg.maxDeviation = 2e16; // 2% tolerance, staleness already set by `_realChainlink`
    _expectSwapRevert(mode, cfg, _amountOutFor((ratio * 90) / 100)); // -10%
  }

  function test_Fork_ChainlinkReal_InverseOut_DirectValidate(uint256 amountIn) public view {
    amountIn = bound(amountIn, 1e6, 1_000_000e6);
    OracleConfig memory cfg = _config(
      _emptyLeg(),
      _chainlinkLeg(CHAINLINK_WBTC_USD, _fullBand(), true, REAL_ORACLE_MAX_STALENESS),
      1e16
    );

    (, uint256 priceOut, uint256 ratio) = _readReal(cfg);

    assertGt(priceOut, 0);
    assertLt(priceOut, 1e18);
    assertEq(ratio, priceOut * 100);

    uint256 realizedPrice = _realizedPriceFor(ratio, amountIn);
    assertTrue(_validateOracle(cfg, tokenIn, tokenOut, realizedPrice));
    assertFalse(_validateOracle(cfg, tokenIn, tokenOut, (ratio * 98) / 100));
  }

  function test_Fork_ChainlinkReal_BothLegs_InverseOut_DirectValidate(uint256 amountIn)
    public
    view
  {
    amountIn = bound(amountIn, 1e6, 1_000_000e6);
    OracleConfig memory cfg = _config(
      _chainlinkLeg(CHAINLINK_USDT_USD, _fullBand(), false, REAL_ORACLE_MAX_STALENESS),
      _chainlinkLeg(CHAINLINK_WBTC_USD, _fullBand(), true, REAL_ORACLE_MAX_STALENESS),
      1e16
    );

    (uint256 priceIn, uint256 priceOut, uint256 ratio) = _readReal(cfg);

    assertGt(priceIn, 0);
    assertGt(priceOut, 0);
    assertLt(priceOut, 1e18);
    assertEq(ratio, ((priceIn * priceOut) / 1e18) * 100);

    uint256 realizedPrice = _realizedPriceFor(ratio, amountIn);
    assertTrue(_validateOracle(cfg, tokenIn, tokenOut, realizedPrice));
    assertFalse(_validateOracle(cfg, tokenIn, tokenOut, (ratio * 98) / 100));
  }
}
