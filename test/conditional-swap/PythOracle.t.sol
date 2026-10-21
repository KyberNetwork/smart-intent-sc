// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './ConditionalSwapBase.t.sol';

import {IMulticall3} from 'forge-std/interfaces/IMulticall3.sol';
import {IPyth} from 'src/interfaces/oracle/external/IPyth.sol';
import {PythOracleAdapter} from 'src/oracle-adapter/PythOracleAdapter.sol';
import {MockPyth} from 'test/mocks/MockPyth.sol';

contract PythOracleTest is ConditionalSwapBaseTest {
  using SafeERC20 for IERC20;
  using TokenHelper for address;
  using ArraysHelper for *;
  using MerkleUtils for *;

  // tokenIn = USDT (6 decimals), tokenOut = WBTC (8 decimals) on the mainnet fork.
  // Per-token USD prices, USD-per-whole-token scaled by 1e18:
  uint256 internal constant USDT_USD = 1e18; // $1
  uint256 internal constant BTC_USD = 100_000e18; // $100k
  // Derived swap ratio (amountOut_raw * 1e36 / amountIn_raw) for the mock prices: 1e33.
  uint256 internal constant ORACLE_RATIO = 1e33;
  // WBTC per whole USD/USDT, scaled by 1e18.
  uint256 internal constant WBTC_PER_USD = 1e13;
  uint256 internal constant WBTC_PER_USDT = WBTC_PER_USD;
  uint256 internal constant USDT_PER_WBTC = 100_000e18;
  uint256 internal constant REAL_ORACLE_MAX_STALENESS = 15 hours;

  uint256 internal constant PYTH_FEE = 0.001 ether;
  uint256 internal constant PYTH_MAX_STALENESS = 30 minutes;
  bytes constant PYTH_UPDATE_DATA =
    hex'504e41550100000003b801000000060d00461ea6caa392697ca4698dbf66f2f00f963c90b5b6db5255e4c85d4dafd6525f680a9abcde11b1d69904f282381b9bd544f88fca66e152589f0c5e9e54cd69180101db5c7584140358639ed9bba2055f9541d08656b01814143b0c8217ae347821f42b0c7685e6fba5d8dea408d72a5ff244e5fab1ccb6f30175c1c0e937618e8cb10102dd360df4be6c68dbe8169d73541384b37b7bba59e5697ab445109fecef919b175cad5cb5fca45255739733c8689fd28580ff30cf68d5e44f8c09457da5dd6ec8000498e4f639087d60bba599b5e105497c86d1771581b401ba0716afa587da23eab777dec74994fdaaa13e2968f0c51869c7f0ba9ace3980fd8e6427b881f0b5fce20105fdbd037cd2e6e28d61e9e2fd7d5be64613d8ff19a0eeafa6b498da3fa210a96a6e4d82f18d4267e006548aafdaa976eab7033ae5a8a3e0dae111d189fa9e9fe10006d654bed39cb4b75553339843a455b35ff0cbbc6fbdb3f55a1023e2a666a23fa75306d9e43d251fc9867ec0eac005a8e3f78f8ec154ae3b5a1c41f2bf78a920e2000802475dfe2082ffc96a6ad714af4384e131827d4192cc7ba2c3f35ccb516c6dfa488b018865c76d8164d971c13409b1bc790101cb780145ab78d8c146f56c46e3010a52f1bb05c9f90f0fb0b80a1e5af9db95e3059190b13f97022f79702618011abc7c5c9bc094a178e3832bdf1f00bad31e8d768ae6814c39c0bce9920f242f45f3000ba32159178fda2fc6d14a9a8616ed8a1feb117f9e22bbdfa86bc1474df78ea9ac23693e676ebef3849534c18bbef80ca488b7930fe550f48a016af34a3b9ddcc1010dfc1051da6e0b4aecbda8f8aac314aae5115b1bf91d09e71d856136f8ac0b48632cadc7a543b435db1e628314673de87e6b128600a580b9190dfdebbc5ba83efd001059b2ce802ee65bd3b1dec19f52a725ff380ce4af224ce27e0c5e8498bfeaae4b7aafb0fdae5949c564e0caab3513736dddcd80742e7ab8f7d2a6565cf7e1099900117b02be79bac0aedcbc82abd111d751b57bb4526afaff97a4c1aadc630bb21a6d09d73f5e7005b72ff6b14a2e8ffc5230eecc98563c8fd1b30b9622252fca2a9c0012d4c28041457a3a001964f75a177d0117c03fdb105a20e6a9e5d23c8f79fa7b5466639b439c2d6a066cfa9611c11c3d78ca1ae9523ea014e66f1a36366d4ef24d006a3b9bdb00000000001ae101faedac5851e32b9b23b5f9411a8c2bac4aae3ed4dd7b811dd1a72ea4aa71000000000cbe08440141555756000000000011cbc1ff00002710dd513a3b10d8385f8fb1b87d90c30741d517e390020055002b89b9dc8fdf9f34709a5b106b472f0f39bb6ca9ce04b0fd7f2e971688e2e53b0000000005f3c81800000000000167e5fffffff8000000006a3b9bdb000000006a3b9bda0000000005f3d446000000000000ed620d7ba6cde7d52e8aa397dc322ed599d8e73dbbe5a791736e606ac2aafad0e62c64c4eeb60baa6a2b77b455e47f0434bdcddc4f7d8a32f706e7fe149238c38ba67a96e5419eb9c4a56a7866d5b732ee190a6d4f34f6bb1a581269e7919a75197b2df72ec6dffeff4b6eeef97b49569e0a0225360f46eb321ff03096e28689aa132bcf4c95f161e8b668a43b96d05f9fdd8e60b22647db7f1cf1aa3f6d27fd88e2e72a8ad0ba703d94d6ec77ff5fa554b0abf001fb2932c0c1861802f1de7c46e3b4142c5117e3767fbbeb7a8d10399ef7be9f56d302ce4587c62650377101a56ad42c948257d9577e8ed671d2868fa7201df4baab12cecfcb177cb715d620e80e1f0a98b82e005500e62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43000005b3f1391dd3000000009ff5722cfffffff8000000006a3b9bdb000000006a3b9bda000005b2daaa2020000000007e076ee80d91ce32105e3cf4383215149cb0515352a28d511addfafa2eea3b08c2a2826cf524dfe185ee61cd53211c4c590ec242e3294e3e9ba697465d6136fd5101a5ac8dceee2b5432ee486de3aaa3700717083fc700c0ce9f84f6348de4b9bcb2fd143be228834d6c3f5c4bb29e1a9c6b2a0e1b222640cf806d221a8a9a87ce117827f45067802ef061c81495c38b6531b6a445f29180a862e0f57e4cbf909f0fbd11c7db59a85d19cef5d2335e397aba5353d6b7c1e496dd3ba08ef9de4d68d6aedb691984467d2fc1206fef134c51f25e85603c7173e6a4dc9750a5e7600500851e116d09ffa2b8a40a48ceb3f976e86c9652f4baab12cecfcb177cb715d620e80e1f0a98b82e';

  bytes32 internal constant USDT_ID = keccak256('USDT/USD');
  bytes32 internal constant WBTC_ID = keccak256('WBTC/USD');

  // --- Real mainnet Pyth ---
  address internal constant PYTH_MAINNET = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;
  address internal constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;
  bytes32 internal constant PYTH_USDT_USD =
    0x2b89b9dc8fdf9f34709a5b106b472f0f39bb6ca9ce04b0fd7f2e971688e2e53b;
  bytes32 internal constant PYTH_BTC_USD =
    0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43;

  MockPyth internal pyth;
  PythOracleAdapter internal pythAdapter;

  function _selectFork() public virtual override {
    vm.createSelectFork('mainnet', 25_386_536);
  }

  function setUp() public virtual override {
    super.setUp();

    pythAdapter = new PythOracleAdapter();

    pyth = new MockPyth(PYTH_FEE);
    pyth.setPrice(USDT_ID, int64(1e8), int32(-8), vm.getBlockTimestamp());
    pyth.setPrice(WBTC_ID, int64(int256(100_000e8)), int32(-8), vm.getBlockTimestamp());
  }

  function _pythLeg(address pyth_, bytes32 priceId, PackedU128 priceLimits, uint256 maxStaleness)
    internal
    view
    returns (TokenOracle memory)
  {
    return _pythLeg(pyth_, priceId, priceLimits, false, maxStaleness);
  }

  function _pythLeg(
    address pyth_,
    bytes32 priceId,
    PackedU128 priceLimits,
    bool inverse,
    uint256 maxStaleness
  ) internal view returns (TokenOracle memory) {
    return TokenOracle(
      toBoolAddress(inverse, address(pythAdapter)),
      toOracleSource(maxStaleness, pyth_),
      priceLimits,
      abi.encode(priceId, type(uint256).max)
    );
  }

  function _realPyth(PackedU128 bandIn, PackedU128 bandOut)
    internal
    view
    returns (OracleConfig memory)
  {
    return _config(
      _pythLeg(PYTH_MAINNET, PYTH_USDT_USD, bandIn, PYTH_MAX_STALENESS),
      _pythLeg(PYTH_MAINNET, PYTH_BTC_USD, bandOut, true, PYTH_MAX_STALENESS),
      0
    );
  }

  function _updateForkPythPrices() internal {
    bytes[] memory updateData = _forkPythUpdateData();
    uint256 fee = IPyth(PYTH_MAINNET).getUpdateFee(updateData);
    vm.deal(address(this), address(this).balance + fee);
    IPyth(PYTH_MAINNET).updatePriceFeeds{value: fee}(updateData);
  }

  function _forkPythUpdateData() internal pure returns (bytes[] memory updateData) {
    updateData = new bytes[](1);
    updateData[0] = PYTH_UPDATE_DATA;
  }

  function _executeWithForkPythUpdateMulticall(
    uint256 mode,
    IntentData memory intentData,
    ActionData memory actionData,
    bool allowRouterFailure
  ) internal returns (IMulticall3.Result[] memory results) {
    (address caller,,) = _getCallerAndSignatures(mode, intentData, actionData);
    bytes memory dkSignature = _getDKSignature(intentData, actionData);
    bytes memory gdSignature = _getGDSignature(intentData, actionData);

    bytes[] memory updateData = _forkPythUpdateData();
    uint256 fee = IPyth(PYTH_MAINNET).getUpdateFee(updateData);

    IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](2);
    calls[0] = IMulticall3.Call3Value({
      target: PYTH_MAINNET,
      allowFailure: false,
      value: fee,
      callData: abi.encodeCall(IPyth.updatePriceFeeds, (updateData))
    });
    calls[1] = IMulticall3.Call3Value({
      target: address(router),
      allowFailure: allowRouterFailure,
      value: 0,
      callData: abi.encodeCall(
        router.execute, (intentData, dkSignature, guardian, gdSignature, actionData)
      )
    });

    vm.deal(caller, caller.balance + fee);
    vm.startPrank(caller);
    results = IMulticall3(MULTICALL3).aggregate3Value{value: fee}(calls);
    vm.stopPrank();

    assertTrue(results[0].success);
    if (!allowRouterFailure) {
      assertTrue(results[1].success);
    }
  }

  function test_Pyth_Validate(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleConfig memory cfg = _config(
      _pythLeg(address(pyth), USDT_ID, _band(USDT_USD, 100, 100), 3600),
      _pythLeg(address(pyth), WBTC_ID, _band(BTC_USD, 100, 100), true, 3600),
      0
    );

    (IntentData memory intentData, ActionData memory actionData) =
      _buildIntentAndAction(_single(cfg), _amountOutFor(ORACLE_RATIO));

    uint256 balBefore = IERC20(tokenOut).balanceOf(mainAddress);
    _executeSwap(mode, intentData, actionData);

    assertGt(IERC20(tokenOut).balanceOf(mainAddress), balBefore);
    assertEq(pyth.updateCount(), 0);
  }

  function test_Pyth_StalePrice_Revert(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleConfig memory cfg = _config(
      // 100s staleness bound
      _pythLeg(address(pyth), USDT_ID, _fullBand(), 100),
      _pythLeg(address(pyth), WBTC_ID, _fullBand(), true, 100),
      0
    );
    // seeded price is too old by the time getPriceNoOlderThan is called in afterExecution
    vm.warp(vm.getBlockTimestamp() + 1000);

    (IntentData memory intentData, ActionData memory actionData) =
      _buildIntentAndAction(_single(cfg), _amountOutFor(ORACLE_RATIO));

    (address caller, bytes memory dk, bytes memory gd) =
      _getCallerAndSignatures(mode, intentData, actionData);
    vm.startPrank(caller);
    vm.expectRevert(MockPyth.StalePrice.selector);
    router.execute(intentData, dk, guardian, gd, actionData);
  }

  function test_Fork_PythReal_Read_Pass(uint256 mode) public {
    mode = bound(mode, 0, 2);
    OracleConfig memory cfg = _realPyth(_fullBand(), _fullBand());

    (IntentData memory intentData, ActionData memory actionData) =
      _buildIntentAndAction(_single(cfg), _amountOutFor(ORACLE_RATIO));

    uint256 balBefore = IERC20(tokenOut).balanceOf(mainAddress);
    _executeWithForkPythUpdateMulticall(mode, intentData, actionData, false);
    assertGt(IERC20(tokenOut).balanceOf(mainAddress), balBefore);

    (uint256 priceIn, uint256 priceOut, uint256 ratio) = _readReal(cfg);
    assertGt(priceIn, 0);
    assertGt(priceOut, 0);
    assertGt(ratio, 0);
  }

  function test_Fork_FullFlow_PythConfidence_Revert(uint256 mode) public {
    mode = bound(mode, 0, 2);
    _updateForkPythPrices();

    IPyth.Price memory p =
      IPyth(PYTH_MAINNET).getPriceNoOlderThan(PYTH_USDT_USD, PYTH_MAX_STALENESS);

    TokenOracle memory inLeg = TokenOracle(
      toBoolAddress(false, address(pythAdapter)),
      toOracleSource(REAL_ORACLE_MAX_STALENESS, PYTH_MAINNET),
      _fullBand(),
      abi.encode(PYTH_USDT_USD, uint256(0))
    );

    TokenOracle memory outLeg = TokenOracle(
      toBoolAddress(true, address(pythAdapter)),
      toOracleSource(REAL_ORACLE_MAX_STALENESS, PYTH_MAINNET),
      _fullBand(),
      abi.encode(PYTH_BTC_USD, 0)
    );
    OracleConfig memory cfg = _config(inLeg, outLeg, 1e17);

    KSConditionalSwapHook.SwapCondition[] memory condition = _single(cfg);
    IntentData memory intentData = _getIntentData(0, type(uint128).max, condition);
    _setUpMainAddress(intentData, false);
    ActionData memory actionData = _getActionData(
      intentData.tokenData,
      abi.encode(tokenIn, tokenOut, swapAmount, 1000, address(router), mainAddress),
      true
    );
    actionData.hookActionData = _hookActionData(0);

    (address caller, bytes memory dk, bytes memory gd) =
      _getCallerAndSignatures(mode, intentData, actionData);
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        PythOracleAdapter.OracleConfidenceTooWide.selector, uint256(p.conf), p.price, 0
      )
    );
    router.execute(intentData, dk, guardian, gd, actionData);
  }

  function test_Fork_PythReal_InverseOut_DirectValidate(uint256 amountIn) public {
    _updateForkPythPrices();
    amountIn = bound(amountIn, 1e6, 1_000_000e6);
    OracleConfig memory cfg = _config(
      _emptyLeg(), _pythLeg(PYTH_MAINNET, PYTH_BTC_USD, _fullBand(), true, PYTH_MAX_STALENESS), 1e16
    );

    (, uint256 priceOut, uint256 ratio) = _readReal(cfg);

    assertGt(priceOut, 0);
    assertLt(priceOut, 1e18);
    assertEq(ratio, priceOut * 1e20);

    uint256 realizedPrice = _realizedPriceFor(ratio, amountIn);
    assertTrue(_validateOracle(cfg, tokenIn, tokenOut, realizedPrice));
    assertFalse(_validateOracle(cfg, tokenIn, tokenOut, (ratio * 98) / 100));
  }

  function test_Fork_PythReal_BothLegs_InverseOut_DirectValidate(uint256 amountIn) public {
    _updateForkPythPrices();
    amountIn = bound(amountIn, 1e6, 1_000_000e6);
    OracleConfig memory cfg = _config(
      _pythLeg(PYTH_MAINNET, PYTH_USDT_USD, _fullBand(), PYTH_MAX_STALENESS),
      _pythLeg(PYTH_MAINNET, PYTH_BTC_USD, _fullBand(), true, PYTH_MAX_STALENESS),
      1e16
    );

    (uint256 priceIn, uint256 priceOut, uint256 ratio) = _readReal(cfg);

    assertGt(priceIn, 0);
    assertGt(priceOut, 0);
    assertLt(priceOut, 1e18);
    assertEq(ratio, priceIn * priceOut * 100);

    uint256 realizedPrice = _realizedPriceFor(ratio, amountIn);
    assertTrue(_validateOracle(cfg, tokenIn, tokenOut, realizedPrice));
    assertFalse(_validateOracle(cfg, tokenIn, tokenOut, (ratio * 98) / 100));
  }
}
