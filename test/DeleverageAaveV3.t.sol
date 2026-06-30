// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './Base.t.sol';

import 'ks-zap-aggregation-public-sc/src/modules/flashloan/FlashLoanAdapter.sol';
import 'ks-zap-aggregation-public-sc/src/modules/lending/aave-v3/AaveV3ActionAdapter.sol';
import 'ks-zap-aggregation-public-sc/src/types/BoolAddress.sol';
import 'ks-zap-aggregation-public-sc/src/types/PackedBits.sol';
import 'ks-zap-aggregation-public-sc/src/vendors/aave-v3/IAaveOracle.sol';

import 'src/hooks/deleverage/KSDeleverageHook.sol';

import 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';

contract DeleverageAaveV3Test is BaseTest {
  using ArraysHelper for *;
  using TokenHelper for address;

  KSDeleverageHook internal hook;
  FlashLoanAdapter internal flashLoanAdapter;
  AaveV3ActionAdapter internal aaveV3Adapter;

  address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

  IPool pool = IPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2); // ethereum v3 core market

  address USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

  struct FuzzStruct {
    uint256 supplyAmount;
    uint256 borrowAmount;
    uint256 repayAmount;
    uint256 withdrawAmount;
    uint256 mode;
  }

  function setUp() public override {
    super.setUp();

    flashLoanAdapter = new FlashLoanAdapter(WETH);
    aaveV3Adapter = new AaveV3ActionAdapter();
    hook = new KSDeleverageHook([address(router)].toMemoryArray(), WETH);

    vm.prank(admin);
    router.grantRole(ACTION_CONTRACT_ROLE, address(mockActionContract));
  }

  function testFuzz_DeleverageAaveV3(FuzzStruct memory fs) public {
    fs.mode = bound(fs.mode, 0, 2);

    address aUSDT = pool.getReserveAToken(USDT);
    fs.borrowAmount = bound(fs.borrowAmount, 1e6, USDT.balanceOf(aUSDT) / 10);
    fs.repayAmount = bound(fs.repayAmount, fs.borrowAmount / 2, fs.borrowAmount);

    uint256 borrowAmountInCol = _convertAmount(USDT, WETH, fs.borrowAmount);
    fs.supplyAmount = bound(fs.supplyAmount, borrowAmountInCol * 3 / 2, borrowAmountInCol * 2);
    deal(WETH, mainAddress, fs.supplyAmount);

    fs.withdrawAmount = _convertAmount(USDT, WETH, fs.repayAmount);

    vm.startPrank(mainAddress);

    WETH.forceApprove(address(pool), type(uint256).max);
    pool.supply(WETH, fs.supplyAmount, mainAddress, 0);
    pool.borrow(USDT, fs.borrowAmount, 2, 0, mainAddress);

    vm.stopPrank();

    IntentData memory intentData = _getIntentData();
    _setUpMainAddress(intentData, false);

    ActionData memory actionData = _getActionData(fs);

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(fs.mode, intentData, actionData);

    vm.startPrank(caller);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function _getIntentData() internal view returns (IntentData memory intentData) {
    IKSDeleverageHook.DeleverageHookIntentParams memory intentParams;
    intentParams.flashLoanAdapter = address(flashLoanAdapter);
    intentParams.swapRouter = address(mockDex);
    intentParams.lendingAdapter = address(aaveV3Adapter);
    intentParams.protocol = IKSDeleverageHook.LENDING_PROTOCOL.AAVE_V3;

    intentData.coreData = IntentCoreData({
      mainAddress: mainAddress,
      signatureVerifier: address(0),
      delegatedKey: delegatedPublicKey,
      actionContracts: [address(mockActionContract)].toMemoryArray(),
      actionSelectors: [mockActionContract.execute.selector].toMemoryArray(),
      hook: address(hook),
      hookIntentData: abi.encode(intentParams)
    });
  }

  function _getActionData(FuzzStruct memory fs) internal returns (ActionData memory actionData) {
    IKSDeleverageHook.DeleverageHookActionParams memory actionParams;
    actionParams.sources = new IFlashLoanAdapter.FlashLoanSource[](1);
    actionParams.sources[0] = IFlashLoanAdapter.FlashLoanSource.AAVE_V3;

    BoolAddress[] memory tokenInfos = new BoolAddress[](1);
    tokenInfos[0] = toBoolAddress(true, WETH);
    actionParams.flashLoanParams = new bytes[](1);
    actionParams.flashLoanParams[0] =
      abi.encode(pool, tokenInfos, [fs.withdrawAmount].toMemoryArray());

    mockDex.setAmountOut(fs.repayAmount);
    deal(USDT, address(mockDex), fs.repayAmount);
    IKSDeleverageHook.DeleverageSubActionParams memory subActionParams =
      IKSDeleverageHook.DeleverageSubActionParams({
        lendingAdapter: address(aaveV3Adapter),
        lendingContext: abi.encode(toBoolAddress(true, address(pool))),
        debtToken: USDT,
        swapRouter: address(mockDex),
        swapData: abi.encodeCall(
          mockDex.execute, (abi.encode(WETH, USDT, hook, fs.withdrawAmount))
        ),
        flags: toPackedBits([true, false].toMemoryArray())
      });
    actionParams.data = new bytes[](1);
    actionParams.data[0] = abi.encode(subActionParams);

    actionData.actionCalldata = abi.encode('');
    actionData.hookActionData = abi.encode(actionParams);
    actionData.deadline = block.timestamp + 1000;
  }

  function _setUpMainAddress(IntentData memory intentData, bool withSignedIntent) internal {
    vm.startPrank(mainAddress);

    address aWETH = pool.getReserveAToken(WETH);
    aWETH.forceApprove(address(hook), type(uint256).max);
    if (!withSignedIntent) {
      router.delegate(intentData);
    }

    vm.stopPrank();
  }

  function _convertAmount(address token0, address token1, uint256 amount0)
    internal
    view
    returns (uint256 amount1)
  {
    address oracle = pool.ADDRESSES_PROVIDER().getPriceOracle();
    uint256[] memory prices = IAaveOracle(oracle).getAssetsPrices([token0, token1].toMemoryArray());
    amount1 = Math.mulDiv(
      amount0,
      prices[0] * (10 ** IERC20Metadata(token1).decimals()),
      prices[1] * (10 ** IERC20Metadata(token0).decimals())
    );
  }
}
