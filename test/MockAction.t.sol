// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.t.sol';

import './mocks/MockHook.sol';

import 'openzeppelin-contracts/contracts/access/IAccessControl.sol';
import 'openzeppelin-contracts/contracts/utils/Base64.sol';
import 'openzeppelin-contracts/contracts/utils/cryptography/verifiers/ERC7913P256Verifier.sol';
import 'openzeppelin-contracts/contracts/utils/cryptography/verifiers/ERC7913WebAuthnVerifier.sol';

contract MockActionTest is BaseTest {
  using ArraysHelper for *;
  using SafeERC20 for IERC20;

  uint256 nonce = 0;
  MockHook mockHook;

  address verifier;

  function setUp() public override {
    super.setUp();

    mockHook = new MockHook();

    vm.makePersistent(address(mockHook));
  }

  function testUpdateForwarder() public {
    forwarder = new KSGenericForwarder();

    vm.prank(makeAddr('random'));
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, makeAddr('random'), 0
      )
    );
    router.updateForwarder(address(forwarder));

    vm.prank(admin);
    vm.expectEmit(true, true, true, true);
    emit IKSSmartIntentRouter.UpdateForwarder(address(forwarder));
    router.updateForwarder(address(forwarder));
  }

  function testMockActionExecuteSuccess(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    vm.prank(mainAddress);
    router.delegate(intentData);
    _checkAllowancesAfterDelegation(intentHash, intentData.tokenData);

    TokenData memory newTokenData = _getNewTokenData(intentData.tokenData, seed);
    ActionData memory actionData = _getActionData(newTokenData, abi.encode(''), seed);

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);

    vm.startPrank(caller);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
    _checkAllowancesAfterExecution(intentHash, intentData.tokenData, newTokenData);
  }

  function testMockActionExecuteSuccessP256(uint256 seed, bool testOnSepolia) public {
    if (testOnSepolia) {
      vm.createSelectFork(vm.envString('SEPOLIA_NODE_URL'), 9_598_379);
    } else {
      vm.createSelectFork(vm.envString('OP_NODE_URL'), 143_581_448);
    }

    _setupP256();

    verifier = address(new ERC7913P256Verifier());

    uint256 mode = bound(seed, 0, 1);
    IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    vm.prank(mainAddress);
    router.delegate(intentData);
    _checkAllowancesAfterDelegation(intentHash, intentData.tokenData);

    TokenData memory newTokenData = _getNewTokenData(intentData.tokenData, seed);
    ActionData memory actionData = _getActionData(newTokenData, abi.encode(''), seed);

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);

    vm.startPrank(caller);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
    _checkAllowancesAfterExecution(intentHash, intentData.tokenData, newTokenData);
  }

  function testMockActionExecuteSuccessWebAuthn(uint256 seed, bool testOnSepolia) public {
    if (testOnSepolia) {
      vm.createSelectFork(vm.envString('SEPOLIA_NODE_URL'), 9_598_379);
    } else {
      vm.createSelectFork(vm.envString('OP_NODE_URL'), 143_581_448);
    }

    _setupP256();

    verifier = address(new ERC7913WebAuthnVerifier());

    uint256 mode = bound(seed, 0, 1);
    IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    vm.prank(mainAddress);
    router.delegate(intentData);
    _checkAllowancesAfterDelegation(intentHash, intentData.tokenData);

    TokenData memory newTokenData = _getNewTokenData(intentData.tokenData, seed);
    ActionData memory actionData = _getActionData(newTokenData, abi.encode(''), seed);

    vm.warp(block.timestamp + 100);
    (address caller,, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);

    bytes memory dkSignature = _getWebAuthnSignature(
      router.hashTypedActionWitness(ActionWitness({intentHash: intentHash, actionData: actionData}))
    );

    vm.startPrank(caller);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
    _checkAllowancesAfterExecution(intentHash, intentData.tokenData, newTokenData);
  }

  function testMockActionExecuteWithSignedIntentSuccess(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    TokenData memory newTokenData = _getNewTokenData(intentData.tokenData, seed);
    ActionData memory actionData = _getActionData(newTokenData, abi.encode(''), seed);

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);

    bytes memory maSignature = _getMASignature(intentData);
    vm.startPrank(caller);
    router.executeWithSignedIntent(
      intentData, maSignature, dkSignature, guardian, gdSignature, actionData
    );
    _checkAllowancesAfterExecution(intentHash, intentData.tokenData, newTokenData);
  }

  function testMockActionCollectERC20MoreThanAllowanceShouldRevert(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    vm.prank(mainAddress);
    router.delegate(intentData);

    TokenData memory newTokenData = _getNewTokenData(intentData.tokenData, seed);
    newTokenData.erc20Data[0].amount =
      intentData.tokenData.erc20Data[0].amount + bound(seed, 1, 1e18);
    ActionData memory actionData = _getActionData(newTokenData, abi.encode(''), seed);

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);

    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        IKSSmartIntentRouter.ERC20InsufficientIntentAllowance.selector,
        intentHash,
        newTokenData.erc20Data[0].token,
        intentData.tokenData.erc20Data[0].amount,
        newTokenData.erc20Data[0].amount
      )
    );
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function testMockActionDelegateWithRandomCallerShouldRevert(uint256 seed) public {
    IntentData memory intentData = _getIntentData(seed);

    vm.prank(randomCaller);
    vm.expectRevert(IKSSmartIntentRouter.NotMainAddress.selector);
    router.delegate(intentData);
  }

  function testMockActionExecuteWithNonWhitelistedActionShouldRevert(uint256 seed) public {
    vm.prank(admin);
    router.revokeRole(ACTION_CONTRACT_ROLE, address(mockActionContract));

    uint256 mode = bound(seed, 0, 2);
    IntentData memory intentData = _getIntentData(seed);

    TokenData memory newTokenData = _getNewTokenData(intentData.tokenData, seed);
    ActionData memory actionData = _getActionData(newTokenData, abi.encode(''), seed);

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);

    bytes memory maSignature = _getMASignature(intentData);
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(mockActionContract),
        ACTION_CONTRACT_ROLE
      )
    );
    router.executeWithSignedIntent(
      intentData, maSignature, dkSignature, guardian, gdSignature, actionData
    );
  }

  function testMockActionExecuteWithNonWhitelistedActionAfterDelegateShouldRevert(uint256 seed)
    public
  {
    uint256 mode = bound(seed, 0, 2);
    IntentData memory intentData = _getIntentData(seed);

    vm.prank(mainAddress);
    router.delegate(intentData);

    vm.prank(admin);
    router.revokeRole(ACTION_CONTRACT_ROLE, address(mockActionContract));

    TokenData memory newTokenData = _getNewTokenData(intentData.tokenData, seed);
    ActionData memory actionData = _getActionData(newTokenData, abi.encode(''), seed);

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);

    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(mockActionContract),
        ACTION_CONTRACT_ROLE
      )
    );
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function testMockActionExecuteRevokedIntentShouldRevert(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IntentData memory intentData = _getIntentData(seed);

    vm.startPrank(mainAddress);
    router.delegate(intentData);
    router.revoke(intentData);
    vm.stopPrank();

    TokenData memory newTokenData = _getNewTokenData(intentData.tokenData, seed);
    ActionData memory actionData = _getActionData(newTokenData, abi.encode(''), seed);

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);

    vm.startPrank(caller);
    vm.expectRevert(IKSSmartIntentRouter.IntentRevoked.selector);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function testMockActionDelegateRevokedIntentWithIntentDataShouldRevert(uint256 seed) public {
    IntentData memory intentData = _getIntentData(seed);

    vm.startPrank(mainAddress);
    router.revoke(intentData);
    vm.expectRevert(IKSSmartIntentRouter.IntentRevoked.selector);
    router.delegate(intentData);
    vm.stopPrank();
  }

  function testMockActionExecuteRevokedIntentWithIntentDataShouldRevert(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IntentData memory intentData = _getIntentData(seed);

    vm.startPrank(mainAddress);
    router.revoke(intentData);
    vm.stopPrank();

    TokenData memory newTokenData = _getNewTokenData(intentData.tokenData, seed);
    ActionData memory actionData = _getActionData(newTokenData, abi.encode(''), seed);

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);

    vm.startPrank(caller);
    vm.expectRevert(IKSSmartIntentRouter.IntentRevoked.selector);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function testMockActionExecuteNotDelegatedIntentShouldRevert(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IntentData memory intentData = _getIntentData(seed);

    TokenData memory newTokenData = _getNewTokenData(intentData.tokenData, seed);
    ActionData memory actionData = _getActionData(newTokenData, abi.encode(''), seed);

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);

    vm.startPrank(caller);
    vm.expectRevert();
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function testMockActionDelegateExistedIntentShouldRevert(uint256 seed) public {
    IntentData memory intentData = _getIntentData(seed);

    vm.startPrank(mainAddress);
    router.delegate(intentData);

    vm.expectRevert(IKSSmartIntentRouter.IntentDelegated.selector);
    router.delegate(intentData);
  }

  function testMockActionExecuteEmptyActionShouldRevert(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IntentData memory intentData = _getIntentData(seed);
    intentData.coreData.actionContracts = new address[](0);
    intentData.coreData.actionSelectors = new bytes4[](0);

    bytes32 intentHash = router.hashTypedIntentData(intentData);

    vm.prank(mainAddress);
    router.delegate(intentData);
    _checkAllowancesAfterDelegation(intentHash, intentData.tokenData);

    TokenData memory newTokenData = _getNewTokenData(intentData.tokenData, seed);
    ActionData memory actionData = _getActionData(newTokenData, abi.encode(''), seed);

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);

    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IKSSmartIntentRouter.InvalidActionSelectorId.selector, 0)
    );
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function testMockActionExecuteActionNotInListActionsShouldRevert(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    vm.prank(mainAddress);
    router.delegate(intentData);
    _checkAllowancesAfterDelegation(intentHash, intentData.tokenData);

    TokenData memory newTokenData = _getNewTokenData(intentData.tokenData, seed);
    ActionData memory actionData = _getActionData(newTokenData, abi.encode(''), seed);
    actionData.actionSelectorId = 1; // set to 1 to make sure the action is not in the list

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);

    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IKSSmartIntentRouter.InvalidActionSelectorId.selector, 1)
    );
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function testMockActionExecuteSuccessShouldEmitExtraData(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    vm.prank(mainAddress);
    router.delegate(intentData);
    _checkAllowancesAfterDelegation(intentHash, intentData.tokenData);

    TokenData memory newTokenData = _getNewTokenData(intentData.tokenData, seed);
    ActionData memory actionData = _getActionData(newTokenData, abi.encode(''), seed);
    actionData.extraData = hex'1234';

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);

    vm.recordLogs();
    vm.startPrank(caller);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
    _checkAllowancesAfterExecution(intentHash, intentData.tokenData, newTokenData);

    Vm.Log[] memory entries = vm.getRecordedLogs();

    for (uint256 i; i < entries.length; i++) {
      if (
        entries[i].topics[0]
          == keccak256(
            'ExecuteIntent(bytes32,(((address,uint256[],uint256[])[],(address,uint256)[],(address,uint256)[]),uint256,bytes,bytes,bytes,uint256),bytes)'
          )
      ) {
        assertEq(entries[i].topics[1], intentHash);
        assertEq(entries[i].data, abi.encode(actionData, new bytes(0)));
      }
    }
  }

  function testMockActionExecuteWithSameNonceShouldRevert(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    vm.prank(mainAddress);
    router.delegate(intentData);
    _checkAllowancesAfterDelegation(intentHash, intentData.tokenData);

    TokenData memory newTokenData = _getNewTokenData(intentData.tokenData, seed);
    ActionData memory actionData = _getActionData(newTokenData, abi.encode(''), seed);
    actionData.nonce = seed;

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);

    vm.startPrank(caller);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
    _checkAllowancesAfterExecution(intentHash, intentData.tokenData, newTokenData);

    vm.expectRevert(
      abi.encodeWithSelector(
        IKSSmartIntentRouter.NonceAlreadyUsed.selector, intentHash, actionData.nonce
      )
    );
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
  }

  function testMockActionCollectFees(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    vm.prank(mainAddress);
    router.delegate(intentData);
    _checkAllowancesAfterDelegation(intentHash, intentData.tokenData);

    TokenData memory newTokenData = _getNewTokenData(intentData.tokenData, seed);
    ActionData memory actionData = _getActionData(
      newTokenData, abi.encode(abi.encode(address(erc20Mock), address(router))), seed
    );

    address[] memory tokens = new address[](1);
    uint256[] memory feesBefore = new uint256[](1);
    uint256[] memory feesAfter = new uint256[](1);
    uint256[] memory amounts = new uint256[](1);
    unchecked {
      tokens[0] = address(erc20Mock);

      feesBefore[0] = bound(seed * 2, 0, actionData.erc20Amounts[0]);
      actionData.hookActionData = abi.encode(feesBefore);

      amounts[0] = bound(seed * 3, 0, actionData.erc20Amounts[0] - feesBefore[0]);
      feesAfter[0] = bound(seed * 3, 0, actionData.erc20Amounts[0] - feesBefore[0] - amounts[0]);
      actionData.extraData = abi.encode(tokens, feesAfter, amounts, address(this));
    }

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);

    vm.startPrank(caller);

    FeeConfig[] memory feeConfigs = _buildPartnersConfigs(
      PartnersFeeConfigBuildParams({
        feeModes: [seed % 2 == 0].toMemoryArray(),
        partnerFees: [uint24(bound(seed, 0, 1e6))].toMemoryArray(),
        partnerRecipients: [partnerRecipient].toMemoryArray()
      })
    );

    (uint256 protocolFeeBefore, uint256[] memory partnersFeeAmountsBefore) =
      this.computeFees(feeConfigs, feesBefore[0]);

    vm.expectEmit(true, true, true, true);
    emit IKSSmartIntentRouter.RecordVolumeAndFees(
      address(erc20Mock),
      protocolRecipient,
      feeConfigs,
      protocolFeeBefore,
      partnersFeeAmountsBefore,
      true,
      actionData.erc20Amounts[0]
    );

    (uint256 protocolFeeAfter, uint256[] memory partnersFeeAmountsAfter) =
      this.computeFees(feeConfigs, feesAfter[0]);
    vm.expectEmit(true, true, true, true);
    emit IKSSmartIntentRouter.RecordVolumeAndFees(
      address(erc20Mock),
      protocolRecipient,
      feeConfigs,
      protocolFeeAfter,
      partnersFeeAmountsAfter,
      false,
      amounts[0] + feesAfter[0]
    );

    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
    _checkAllowancesAfterExecution(intentHash, intentData.tokenData, newTokenData);

    assertEq(erc20Mock.balanceOf(address(this)), amounts[0]);
    if (feeConfigs[0].feeMode()) {
      assertEq(
        erc20Mock.balanceOf(protocolRecipient),
        feesBefore[0] + feesAfter[0],
        'Protocol recipient did not receive expected fees'
      );
    } else {
      assertEq(
        erc20Mock.balanceOf(protocolRecipient),
        protocolFeeBefore + protocolFeeAfter,
        'Protocol recipient did not receive expected fees'
      );
      assertEq(
        erc20Mock.balanceOf(partnerRecipient),
        partnersFeeAmountsBefore[0] + partnersFeeAmountsAfter[0],
        'Partner recipient did not receive expected fees'
      );
    }
  }

  function computeFees(FeeConfig[] calldata self, uint256 totalAmount)
    external
    pure
    returns (uint256 protocolFeeAmount, uint256[] memory partnersFeeAmounts)
  {
    return FeeInfoLibrary.computeFees(self, totalAmount);
  }

  function hash(ActionData calldata self) external pure returns (bytes32) {
    return self.hash();
  }

  function _getNewTokenData(TokenData memory tokenData, uint256 seed)
    internal
    view
    returns (TokenData memory newTokenData)
  {
    newTokenData.erc20Data = new ERC20Data[](1);
    newTokenData.erc20Data[0] = ERC20Data({
      token: address(erc20Mock),
      amount: bound(seed, 1, tokenData.erc20Data[0].amount),
      permitData: ''
    });

    newTokenData.erc721Data = new ERC721Data[](1);
    newTokenData.erc721Data[0] =
      ERC721Data({token: address(erc721Mock), tokenId: seed, permitData: ''});
  }

  function _getIntentData(uint256 seed) internal returns (IntentData memory intentData) {
    vm.startPrank(mainAddress);
    IntentCoreData memory coreData = IntentCoreData({
      mainAddress: mainAddress,
      signatureVerifier: verifier,
      delegatedKey: delegatedPublicKey,
      actionContracts: [address(mockActionContract)].toMemoryArray(),
      actionSelectors: [MockActionContract.execute.selector].toMemoryArray(),
      hook: address(mockHook),
      hookIntentData: ''
    });

    TokenData memory tokenData;

    tokenData.erc20Data = new ERC20Data[](1);
    tokenData.erc20Data[0] =
      ERC20Data({token: address(erc20Mock), amount: bound(seed, 1, 1e18), permitData: ''});
    erc20Mock.mint(mainAddress, tokenData.erc20Data[0].amount);
    erc20Mock.approve(address(router), tokenData.erc20Data[0].amount);

    tokenData.erc721Data = new ERC721Data[](1);
    tokenData.erc721Data[0] =
      ERC721Data({token: address(erc721Mock), tokenId: seed, permitData: ''});
    erc721Mock.mint(mainAddress, seed);
    erc721Mock.approve(address(router), seed);

    intentData = IntentData({coreData: coreData, tokenData: tokenData, extraData: ''});
    vm.stopPrank();
  }

  function _getActionData(TokenData memory tokenData, bytes memory actionCalldata, uint256 seed)
    internal
    returns (ActionData memory actionData)
  {
    uint256 approvalFlags = (1 << (tokenData.erc20Data.length + tokenData.erc721Data.length)) - 1;

    uint256[] memory erc20Amounts = new uint256[](tokenData.erc20Data.length);
    for (uint256 i = 0; i < tokenData.erc20Data.length; i++) {
      erc20Amounts[i] = tokenData.erc20Data[i].amount;
    }

    FeeInfo memory feeInfo;
    {
      feeInfo.protocolRecipient = protocolRecipient;
      feeInfo.partnerFeeConfigs = new FeeConfig[][](1);
      feeInfo.partnerFeeConfigs[0] = _buildPartnersConfigs(
        PartnersFeeConfigBuildParams({
          feeModes: [seed % 2 == 0].toMemoryArray(),
          partnerFees: [uint24(bound(seed, 0, 1e6))].toMemoryArray(),
          partnerRecipients: [partnerRecipient].toMemoryArray()
        })
      );
    }

    actionData = ActionData({
      erc20Ids: _consecutiveArray(0, tokenData.erc20Data.length),
      erc20Amounts: erc20Amounts,
      erc721Ids: _consecutiveArray(0, tokenData.erc721Data.length),
      feeInfo: feeInfo,
      approvalFlags: approvalFlags,
      actionSelectorId: 0,
      actionCalldata: actionCalldata,
      hookActionData: '',
      extraData: '',
      deadline: block.timestamp + 1 days,
      nonce: nonce++
    });
  }

  function _checkAllowancesAfterDelegation(bytes32 intentHash, TokenData memory tokenData)
    internal
    view
  {
    for (uint256 i = 0; i < tokenData.erc20Data.length; i++) {
      ERC20Data memory erc20Data = tokenData.erc20Data[i];
      assertEq(
        router.erc20Allowances(intentHash, erc20Data.token),
        erc20Data.amount,
        'ERC20 allowance not set correctly after delegation'
      );
    }
  }

  function _checkAllowancesAfterExecution(
    bytes32 intentHash,
    TokenData memory tokenData,
    TokenData memory newTokenData
  ) internal view {
    for (uint256 i = 0; i < tokenData.erc20Data.length; i++) {
      ERC20Data memory erc20Data = tokenData.erc20Data[i];
      assertEq(
        router.erc20Allowances(intentHash, erc20Data.token),
        erc20Data.amount - newTokenData.erc20Data[i].amount,
        'ERC20 allowance not updated correctly after execution'
      );
    }
  }

  function _consecutiveArray(uint256 start, uint256 end) internal pure returns (uint256[] memory) {
    uint256[] memory array = new uint256[](end - start);
    for (uint256 i = start; i < end; i++) {
      array[i - start] = i;
    }
    return array;
  }

  function _getWebAuthnSignature(bytes32 witnessHash)
    internal
    view
    returns (bytes memory signature)
  {
    bytes memory authenicatorData = _encodeAuthenticatorData(
      WebAuthn.AUTH_DATA_FLAGS_UP | WebAuthn.AUTH_DATA_FLAGS_UV
    );
    string memory clientDataJSON = _encodeClientDataJSON(abi.encodePacked(witnessHash));

    bytes32 messageHash = sha256(abi.encodePacked(authenicatorData, sha256(bytes(clientDataJSON))));
    (bytes32 r, bytes32 s) = vm.signP256(delegatedPrivateKey, messageHash);

    WebAuthn.WebAuthnAuth memory webAuthnAuth = WebAuthn.WebAuthnAuth({
      r: r,
      s: s,
      challengeIndex: 23,
      typeIndex: 1,
      authenticatorData: authenicatorData,
      clientDataJSON: clientDataJSON
    });

    bytes memory encoded = abi.encode(webAuthnAuth);

    signature = new bytes(encoded.length - 32);
    assembly ('memory-safe') {
      mcopy(add(signature, 32), add(encoded, 64), sub(mload(encoded), 32))
    }
  }

  function _encodeAuthenticatorData(bytes1 flags) internal pure returns (bytes memory) {
    return abi.encodePacked(bytes32(0), flags, bytes4(0));
  }

  function _encodeClientDataJSON(bytes memory challenge) internal pure returns (string memory) {
    // solhint-disable-next-line quotes
    return string.concat('{"type":"webauthn.get","challenge":"', Base64.encodeURL(challenge), '"}');
  }
}
