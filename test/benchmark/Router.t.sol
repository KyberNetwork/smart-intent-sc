// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../Base.t.sol';
import '../mocks/MockHook.sol';

import 'openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol';
import 'src/hooks/swap/KSSwapHook.sol';

import 'test/benchmark/CalldataGasCalculator.sol';
import 'test/common/Permit.sol';

contract RouterBenchmarkTest is BaseTest {
  using SafeERC20 for IERC20;
  using ArraysHelper for *;

  MockHook mockHook;
  address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  bytes32 usdcPermitTypeHash = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
  bytes32 usdcDomainSep = 0x06c37168a7db5138defc7866392bb87a741f9b3d104deb5094588ce041cae335;

  address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
  bytes32 daiPermitTypeHash = 0xea2aa0a1be11a07ed86d755c93467f4f82362b452371d1ba94d1715123511acb;
  bytes32 daiDomainSep = 0xdbb8cf42e1ecb028be3f3dbc922e1d878b963f411dc388ced501601c60f7c6f7;

  address uniV4PM = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;

  function setUp() public override {
    super.setUp();

    mockHook = new MockHook();
  }

  function testDelegate_OneERC20() public {
    uint256 tokenCount = 1;
    IntentData memory intentData;

    IntentCoreData memory coreData = IntentCoreData({
      mainAddress: mainAddress,
      delegatedAddress: delegatedAddress,
      actionContracts: [address(0)].toMemoryArray(),
      actionSelectors: [bytes4(0)].toMemoryArray(),
      hook: address(0),
      hookIntentData: ''
    });

    TokenData memory tokenData;
    tokenData.erc20Data = new ERC20Data[](tokenCount);
    for (uint256 i; i < tokenCount; i++) {
      tokenData.erc20Data[i] = ERC20Data({token: makeAddr('erc20'), amount: 1e18, permitData: ''});
    }

    vm.startPrank(mainAddress);
    router.delegate(IntentData({coreData: coreData, tokenData: tokenData, extraData: ''}));
    vm.snapshotGasLastCall('test_delegate_erc20_1_token');
  }

  function testDelegate_USDC_NoPermit() public {
    uint256 tokenCount = 1;
    IntentData memory intentData;

    IntentCoreData memory coreData = IntentCoreData({
      mainAddress: mainAddress,
      delegatedAddress: delegatedAddress,
      actionContracts: [address(0)].toMemoryArray(),
      actionSelectors: [bytes4(0)].toMemoryArray(),
      hook: address(0),
      hookIntentData: ''
    });

    TokenData memory tokenData;
    tokenData.erc20Data = new ERC20Data[](tokenCount);
    for (uint256 i; i < tokenCount; i++) {
      tokenData.erc20Data[i] = ERC20Data({token: usdc, amount: 1e18, permitData: ''});
    }

    vm.startPrank(mainAddress);
    router.delegate(IntentData({coreData: coreData, tokenData: tokenData, extraData: ''}));
    vm.snapshotGasLastCall('test_delegate_usdc_no_permit');
  }

  function testDelegate_USDC_Permit() public {
    uint256 tokenCount = 1;
    IntentData memory intentData;

    IntentCoreData memory coreData = IntentCoreData({
      mainAddress: mainAddress,
      delegatedAddress: delegatedAddress,
      actionContracts: [address(0)].toMemoryArray(),
      actionSelectors: [bytes4(0)].toMemoryArray(),
      hook: address(0),
      hookIntentData: ''
    });

    TokenData memory tokenData;
    tokenData.erc20Data = new ERC20Data[](tokenCount);
    for (uint256 i; i < tokenCount; i++) {
      tokenData.erc20Data[i] = ERC20Data({token: usdc, amount: 1e18, permitData: _usdcPermit()});
    }

    vm.startPrank(mainAddress);
    router.delegate(IntentData({coreData: coreData, tokenData: tokenData, extraData: ''}));
    vm.snapshotGasLastCall('test_delegate_usdc_permit');
  }

  function testDelegate_DAI_USDC_NoPermit() public {
    IntentData memory intentData;

    IntentCoreData memory coreData = IntentCoreData({
      mainAddress: mainAddress,
      delegatedAddress: delegatedAddress,
      actionContracts: [address(0)].toMemoryArray(),
      actionSelectors: [bytes4(0)].toMemoryArray(),
      hook: address(0),
      hookIntentData: ''
    });

    TokenData memory tokenData;
    tokenData.erc20Data = new ERC20Data[](2);
    tokenData.erc20Data[0] = ERC20Data({token: dai, amount: 1e18, permitData: ''});
    tokenData.erc20Data[1] = ERC20Data({token: usdc, amount: 1e18, permitData: ''});

    vm.startPrank(mainAddress);
    router.delegate(IntentData({coreData: coreData, tokenData: tokenData, extraData: ''}));
    vm.snapshotGasLastCall('test_delegate_dai_usdc_no_permit');
  }

  function testDelegate_DAI_USDC_Permit() public {
    IntentData memory intentData;

    IntentCoreData memory coreData = IntentCoreData({
      mainAddress: mainAddress,
      delegatedAddress: delegatedAddress,
      actionContracts: [address(0)].toMemoryArray(),
      actionSelectors: [bytes4(0)].toMemoryArray(),
      hook: address(0),
      hookIntentData: ''
    });

    TokenData memory tokenData;
    tokenData.erc20Data = new ERC20Data[](2);
    tokenData.erc20Data[0] = ERC20Data({token: dai, amount: 1e18, permitData: _daiPermit()});
    tokenData.erc20Data[1] = ERC20Data({token: usdc, amount: 1e18, permitData: _usdcPermit()});

    vm.startPrank(mainAddress);
    router.delegate(IntentData({coreData: coreData, tokenData: tokenData, extraData: ''}));
    vm.snapshotGasLastCall('test_delegate_dai_usdc_permit');
  }

  function testDelegate_TwoERC20() public {
    IntentData memory intentData;

    IntentCoreData memory coreData = IntentCoreData({
      mainAddress: mainAddress,
      delegatedAddress: delegatedAddress,
      actionContracts: [address(0)].toMemoryArray(),
      actionSelectors: [bytes4(0)].toMemoryArray(),
      hook: address(0),
      hookIntentData: ''
    });

    TokenData memory tokenData;
    tokenData.erc20Data = new ERC20Data[](2);
    tokenData.erc20Data[0] = ERC20Data({token: makeAddr('erc20_0'), amount: 1e18, permitData: ''});
    tokenData.erc20Data[1] = ERC20Data({token: makeAddr('erc20_1'), amount: 1e18, permitData: ''});

    vm.startPrank(mainAddress);
    router.delegate(IntentData({coreData: coreData, tokenData: tokenData, extraData: ''}));
    vm.snapshotGasLastCall('test_delegate_erc20_2_token');
  }

  function testDelegate_OneERC721() public {
    IntentData memory intentData;

    IntentCoreData memory coreData = IntentCoreData({
      mainAddress: mainAddress,
      delegatedAddress: delegatedAddress,
      actionContracts: [address(0)].toMemoryArray(),
      actionSelectors: [bytes4(0)].toMemoryArray(),
      hook: address(0),
      hookIntentData: ''
    });

    TokenData memory tokenData;
    tokenData.erc721Data = new ERC721Data[](1);
    tokenData.erc721Data[0] = ERC721Data({token: makeAddr('erc721'), tokenId: 1, permitData: ''});

    vm.startPrank(mainAddress);
    router.delegate(IntentData({coreData: coreData, tokenData: tokenData, extraData: ''}));

    bytes memory callData = abi.encodeWithSelector(
      router.delegate.selector,
      IntentData({coreData: coreData, tokenData: tokenData, extraData: ''})
    );
    (uint256 totalGas, uint256 zeroBytesCount, uint256 nonZeroBytesCount) =
      this.calculateCalldataGas(callData);
    console.log('totalGas', totalGas);
    console.log('zeroBytesCount', zeroBytesCount);
    console.log('nonZeroBytesCount', nonZeroBytesCount);
    vm.snapshotGasLastCall('test_delegate_erc721');
  }

  function calculateCalldataGas(bytes calldata callData)
    public
    view
    returns (uint256 totalGas, uint256 zeroBytesCount, uint256 nonZeroBytesCount)
  {
    (totalGas, zeroBytesCount, nonZeroBytesCount) =
      CalldataGasCalculator.calculateCalldataGas(callData);
  }

  function testDelegate_UniV4Position_NoPermit() public {
    IntentData memory intentData;

    IntentCoreData memory coreData = IntentCoreData({
      mainAddress: mainAddress,
      delegatedAddress: delegatedAddress,
      actionContracts: [address(0)].toMemoryArray(),
      actionSelectors: [bytes4(0)].toMemoryArray(),
      hook: address(0),
      hookIntentData: ''
    });

    TokenData memory tokenData;
    tokenData.erc721Data = new ERC721Data[](1);
    tokenData.erc721Data[0] = ERC721Data({token: uniV4PM, tokenId: 1, permitData: ''});

    vm.startPrank(mainAddress);
    router.delegate(IntentData({coreData: coreData, tokenData: tokenData, extraData: ''}));
    vm.snapshotGasLastCall('test_delegate_uniV4Position_no_permit');
  }

  function testDelegate_UniV4Position_Permit() public {
    IntentData memory intentData;

    IntentCoreData memory coreData = IntentCoreData({
      mainAddress: mainAddress,
      delegatedAddress: delegatedAddress,
      actionContracts: [address(0)].toMemoryArray(),
      actionSelectors: [bytes4(0)].toMemoryArray(),
      hook: address(0),
      hookIntentData: ''
    });

    dealERC721(uniV4PM, mainAddress, 1);

    bytes32 digest =
      Permit.uniswapV4Permit(uniV4PM, address(router), 1, 0, block.timestamp + 1 days);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(mainAddressKey, digest);
    bytes memory signature = abi.encodePacked(r, s, v);

    bytes memory permitData = abi.encode(block.timestamp + 1 days, 0, signature);

    TokenData memory tokenData;
    tokenData.erc721Data = new ERC721Data[](1);
    tokenData.erc721Data[0] = ERC721Data({token: uniV4PM, tokenId: 1, permitData: permitData});

    vm.startPrank(mainAddress);
    router.delegate(IntentData({coreData: coreData, tokenData: tokenData, extraData: ''}));
    vm.snapshotGasLastCall('test_delegate_uniV4Position_permit');
  }

  function testDelegate_OneErc721_OneErc20() public {
    IntentData memory intentData;

    IntentCoreData memory coreData = IntentCoreData({
      mainAddress: mainAddress,
      delegatedAddress: delegatedAddress,
      actionContracts: [address(0)].toMemoryArray(),
      actionSelectors: [bytes4(0)].toMemoryArray(),
      hook: address(0),
      hookIntentData: ''
    });

    TokenData memory tokenData;
    tokenData.erc721Data = new ERC721Data[](1);
    tokenData.erc20Data = new ERC20Data[](1);

    tokenData.erc20Data[0] = ERC20Data({token: makeAddr('erc20'), amount: 1e18, permitData: ''});
    tokenData.erc721Data[0] = ERC721Data({token: makeAddr('erc721'), tokenId: 1, permitData: ''});

    vm.startPrank(mainAddress);
    router.delegate(IntentData({coreData: coreData, tokenData: tokenData, extraData: ''}));
    vm.snapshotGasLastCall('test_delegate_erc721_1_erc20');
  }

  function testDelegate_OneErc721_TwoErc20() public {
    IntentData memory intentData;

    IntentCoreData memory coreData = IntentCoreData({
      mainAddress: mainAddress,
      delegatedAddress: delegatedAddress,
      actionContracts: [address(0)].toMemoryArray(),
      actionSelectors: [bytes4(0)].toMemoryArray(),
      hook: address(0),
      hookIntentData: ''
    });

    TokenData memory tokenData;
    tokenData.erc721Data = new ERC721Data[](1);
    tokenData.erc20Data = new ERC20Data[](2);

    tokenData.erc20Data[0] = ERC20Data({token: makeAddr('erc20_0'), amount: 1e18, permitData: ''});
    tokenData.erc20Data[1] = ERC20Data({token: makeAddr('erc20_1'), amount: 1e18, permitData: ''});
    tokenData.erc721Data[0] = ERC721Data({token: makeAddr('erc721'), tokenId: 1, permitData: ''});

    vm.startPrank(mainAddress);
    router.delegate(IntentData({coreData: coreData, tokenData: tokenData, extraData: ''}));
    vm.snapshotGasLastCall('test_delegate_erc721_2_erc20');
  }

  function testExecute_OneErc20() public {
    IntentData memory intentData = _getIntentData(1, false, '');

    ActionData memory actionData = _getActionData(intentData.tokenData, 0, abi.encode(''), '', '');
    vm.prank(mainAddress);
    router.delegate(intentData);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(actionData);
    vm.startPrank(caller);
    router.execute(intentData, daSignature, guardian, gdSignature, actionData);

    vm.snapshotGasLastCall('test_execute_erc20');
  }

  function testExecute_Erc721Only() public {
    IntentData memory intentData = _getIntentData(0, true, '');
    ActionData memory actionData = _getActionData(intentData.tokenData, 0, abi.encode(''), '', '');
    vm.prank(mainAddress);
    router.delegate(intentData);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(actionData);
    vm.startPrank(caller);
    router.execute(intentData, daSignature, guardian, gdSignature, actionData);
  }

  function testExecute_OneErc721_OneErc20() public {
    IntentData memory intentData = _getIntentData(1, true, '');

    ActionData memory actionData = _getActionData(intentData.tokenData, 0, abi.encode(''), '', '');
    vm.prank(mainAddress);
    router.delegate(intentData);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(actionData);
    vm.startPrank(caller);
    router.execute(intentData, daSignature, guardian, gdSignature, actionData);

    vm.snapshotGasLastCall('test_execute_1_erc721_1_erc20');
  }

  function testExecute_TwoErc20() public {
    IntentData memory intentData = _getIntentData(2, false, '');

    ActionData memory actionData = _getActionData(intentData.tokenData, 0, abi.encode(''), '', '');
    vm.prank(mainAddress);
    router.delegate(intentData);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(actionData);
    vm.startPrank(caller);
    router.execute(intentData, daSignature, guardian, gdSignature, actionData);

    vm.snapshotGasLastCall('test_execute_2_erc20');
  }

  function testExecute_OneErc721_TwoErc20() public {
    IntentData memory intentData = _getIntentData(2, true, '');

    ActionData memory actionData = _getActionData(intentData.tokenData, 0, abi.encode(''), '', '');
    vm.prank(mainAddress);
    router.delegate(intentData);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(actionData);
    vm.startPrank(caller);
    router.execute(intentData, daSignature, guardian, gdSignature, actionData);

    vm.snapshotGasLastCall('test_execute_1_erc721_2_erc20');
  }

  function testExecute_OneErc721Only() public {
    IntentData memory intentData = _getIntentData(0, true, '');
    ActionData memory actionData = _getActionData(intentData.tokenData, 0, abi.encode(''), '', '');
    vm.prank(mainAddress);
    router.delegate(intentData);

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(actionData);
    vm.startPrank(caller);
    router.execute(intentData, daSignature, guardian, gdSignature, actionData);

    vm.snapshotGasLastCall('test_execute_1_erc721');
  }

  function testExecuteSignedIntent_OneErc20() public {
    IntentData memory intentData = _getIntentData(1, false, '');
    ActionData memory actionData = _getActionData(intentData.tokenData, 0, abi.encode(''), '', '');

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(actionData);

    bytes memory maSignature = _getMASignature(intentData);
    vm.prank(mainAddress);
    router.executeWithSignedIntent(
      intentData, maSignature, daSignature, guardian, gdSignature, actionData
    );

    vm.snapshotGasLastCall('test_execute_signed_intent_erc20');
  }

  function testExecuteSignedIntent_OneErc20_OneErc721() public {
    IntentData memory intentData = _getIntentData(1, true, '');
    ActionData memory actionData = _getActionData(intentData.tokenData, 0, abi.encode(''), '', '');

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(actionData);

    bytes memory maSignature = _getMASignature(intentData);
    vm.prank(mainAddress);
    router.executeWithSignedIntent(
      intentData, maSignature, daSignature, guardian, gdSignature, actionData
    );

    vm.snapshotGasLastCall('test_execute_signed_intent_erc20_1_erc721');
  }

  function testExecuteSignedIntent_OneErc721Only() public {
    IntentData memory intentData = _getIntentData(0, true, '');
    ActionData memory actionData = _getActionData(intentData.tokenData, 0, abi.encode(''), '', '');

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(actionData);

    bytes memory maSignature = _getMASignature(intentData);
    vm.prank(mainAddress);
    router.executeWithSignedIntent(
      intentData, maSignature, daSignature, guardian, gdSignature, actionData
    );

    vm.snapshotGasLastCall('test_execute_signed_intent_erc721');
  }

  function testExecuteSignedIntent_TwoErc20() public {
    IntentData memory intentData = _getIntentData(2, false, '');
    ActionData memory actionData = _getActionData(intentData.tokenData, 0, abi.encode(''), '', '');

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(actionData);

    bytes memory maSignature = _getMASignature(intentData);
    vm.prank(mainAddress);
    router.executeWithSignedIntent(
      intentData, maSignature, daSignature, guardian, gdSignature, actionData
    );

    vm.snapshotGasLastCall('test_execute_signed_intent_2_erc20');
  }

  function testExecuteSignedIntent_TwoErc20_OneErc721() public {
    IntentData memory intentData = _getIntentData(2, true, '');
    ActionData memory actionData = _getActionData(intentData.tokenData, 0, abi.encode(''), '', '');

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(actionData);

    bytes memory maSignature = _getMASignature(intentData);
    vm.prank(mainAddress);
    router.executeWithSignedIntent(
      intentData, maSignature, daSignature, guardian, gdSignature, actionData
    );

    vm.snapshotGasLastCall('test_execute_signed_intent_2_erc20_1_erc721');
  }

  function testExecuteSignedIntent_WithFee_2_tokens() public {
    IntentData memory intentData = _getIntentData(2, false, '');
    ActionData memory actionData = _getActionData(
      intentData.tokenData, 0, '', abi.encode([uint256(0.1 ether), 0.1 ether].toMemoryArray()), ''
    );

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(actionData);

    bytes memory maSignature = _getMASignature(intentData);
    vm.prank(mainAddress);
    router.executeWithSignedIntent(
      intentData, maSignature, daSignature, guardian, gdSignature, actionData
    );

    vm.snapshotGasLastCall('test_execute_signed_intent_with_fee_2_tokens');
  }

  function testExecuteSignedIntent_WithFeeAfter_1_tokens() public {
    IntentData memory intentData = _getIntentData(1, false, '');
    ActionData memory actionData = _getActionData(
      intentData.tokenData,
      1,
      abi.encode(abi.encode(address(erc20Mock), address(router))),
      abi.encode([uint256(0)].toMemoryArray()),
      abi.encode(
        [address(erc20Mock)].toMemoryArray(),
        [uint256(0.1 ether)].toMemoryArray(),
        [uint256(0.9 ether)].toMemoryArray(),
        mainAddress
      )
    );

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(actionData);

    bytes memory maSignature = _getMASignature(intentData);
    vm.prank(mainAddress);
    router.executeWithSignedIntent(
      intentData, maSignature, daSignature, guardian, gdSignature, actionData
    );

    vm.snapshotGasLastCall('test_execute_signed_intent_with_fee_after_1_tokens');
  }

  function testExecuteSignedIntent_WithFeeAfter_2_tokens() public {
    IntentData memory intentData = _getIntentData(2, false, '');
    ActionData memory actionData = _getActionData(
      intentData.tokenData,
      2,
      abi.encode(
        abi.encode([address(erc20Mock), address(erc20Mock2)].toMemoryArray(), address(router))
      ),
      abi.encode([uint256(0), 0].toMemoryArray()),
      abi.encode(
        [address(erc20Mock), address(erc20Mock2)].toMemoryArray(),
        [uint256(0.1 ether), 0.1 ether].toMemoryArray(),
        [uint256(0.9 ether), 0.9 ether].toMemoryArray(),
        mainAddress
      )
    );

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(actionData);

    bytes memory maSignature = _getMASignature(intentData);
    vm.prank(mainAddress);
    router.executeWithSignedIntent(
      intentData, maSignature, daSignature, guardian, gdSignature, actionData
    );

    vm.snapshotGasLastCall('test_execute_signed_intent_with_fee_after_2_tokens');
  }

  function testExecuteSignedIntent_WithFee_1_tokens() public {
    IntentData memory intentData = _getIntentData(1, false, '');
    ActionData memory actionData = _getActionData(
      intentData.tokenData, 0, '', abi.encode([uint256(0.1 ether)].toMemoryArray()), ''
    );

    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(actionData);

    bytes memory maSignature = _getMASignature(intentData);
    vm.prank(mainAddress);
    router.executeWithSignedIntent(
      intentData, maSignature, daSignature, guardian, gdSignature, actionData
    );

    vm.snapshotGasLastCall('test_execute_signed_intent_with_fee_1_tokens');
  }

  function _getIntentData(uint256 tokenCount, bool hasErc721, bytes memory hookData)
    internal
    returns (IntentData memory intentData)
  {
    vm.startPrank(mainAddress);
    IntentCoreData memory coreData = IntentCoreData({
      mainAddress: mainAddress,
      delegatedAddress: delegatedAddress,
      actionContracts: [
        address(mockActionContract),
        address(mockActionContract),
        address(mockActionContract)
      ].toMemoryArray(),
      actionSelectors: [
        MockActionContract.doNothing.selector,
        mockActionContract.execute.selector,
        mockActionContract.execute2.selector
      ].toMemoryArray(),
      hook: address(mockHook),
      hookIntentData: hookData
    });

    TokenData memory tokenData;

    if (tokenCount == 1) {
      tokenData.erc20Data = new ERC20Data[](1);
      tokenData.erc20Data[0] =
        ERC20Data({token: address(erc20Mock), amount: 100 ether, permitData: ''});
      erc20Mock.mint(mainAddress, tokenData.erc20Data[0].amount);
      erc20Mock.approve(address(router), tokenData.erc20Data[0].amount);
    } else if (tokenCount == 2) {
      tokenData.erc20Data = new ERC20Data[](2);
      tokenData.erc20Data[0] =
        ERC20Data({token: address(erc20Mock), amount: 100 ether, permitData: ''});
      tokenData.erc20Data[1] =
        ERC20Data({token: address(erc20Mock2), amount: 100 ether, permitData: ''});
      erc20Mock.mint(mainAddress, tokenData.erc20Data[0].amount);
      erc20Mock.approve(address(router), tokenData.erc20Data[0].amount);
      erc20Mock2.mint(mainAddress, tokenData.erc20Data[1].amount);
      erc20Mock2.approve(address(router), tokenData.erc20Data[1].amount);
    }

    if (hasErc721) {
      tokenData.erc721Data = new ERC721Data[](1);
      tokenData.erc721Data[0] = ERC721Data({token: address(erc721Mock), tokenId: 1, permitData: ''});
      erc721Mock.mint(mainAddress, 1);
      erc721Mock.approve(address(router), 1);
    }

    intentData = IntentData({coreData: coreData, tokenData: tokenData, extraData: ''});
    vm.stopPrank();
  }

  function _getActionData(
    TokenData memory tokenData,
    uint256 actionSelectorId,
    bytes memory actionCalldata,
    bytes memory hookActionData,
    bytes memory extraData
  ) internal returns (ActionData memory actionData) {
    uint256 approvalFlags = (1 << (tokenData.erc20Data.length + tokenData.erc721Data.length)) - 1;

    uint256[] memory erc20Amounts = new uint256[](tokenData.erc20Data.length);
    for (uint256 i = 0; i < tokenData.erc20Data.length; i++) {
      erc20Amounts[i] = tokenData.erc20Data[i].amount;
    }

    actionData = ActionData({
      erc20Ids: _consecutiveArray(0, tokenData.erc20Data.length),
      erc20Amounts: erc20Amounts,
      erc721Ids: _consecutiveArray(0, tokenData.erc721Data.length),
      approvalFlags: approvalFlags,
      actionSelectorId: actionSelectorId,
      actionCalldata: actionCalldata,
      hookActionData: hookActionData,
      extraData: extraData,
      deadline: block.timestamp + 1 days,
      nonce: 0
    });
  }

  function _consecutiveArray(uint256 start, uint256 end) internal pure returns (uint256[] memory) {
    uint256[] memory array = new uint256[](end - start);
    for (uint256 i = start; i < end; i++) {
      array[i - start] = i;
    }
    return array;
  }

  function _getCallerAndSignatures(ActionData memory actionData)
    internal
    view
    returns (address caller, bytes memory daSignature, bytes memory gdSignature)
  {
    caller = randomCaller;
    daSignature = _getDASignature(actionData);
    gdSignature = _getGDSignature(actionData);
  }

  function _usdcPermit() internal returns (bytes memory) {
    bytes32 typedDataHash = MessageHashUtils.toTypedDataHash(
      usdcDomainSep,
      keccak256(
        abi.encode(
          usdcPermitTypeHash,
          mainAddress,
          address(router),
          10_000_000 ether,
          0,
          block.timestamp + 10 days
        )
      )
    );

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(mainAddressKey, typedDataHash);
    return abi.encode(10_000_000 ether, block.timestamp + 10 days, v, r, s);
  }

  function _daiPermit() internal returns (bytes memory) {
    bytes32 digest = keccak256(
      abi.encodePacked(
        '\x19\x01',
        daiDomainSep,
        keccak256(
          abi.encode(
            daiPermitTypeHash, mainAddress, address(router), 0, block.timestamp + 10 days, true
          )
        )
      )
    );

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(mainAddressKey, digest);
    return abi.encode(0, block.timestamp + 10 days, true, v, r, s);
  }
}
