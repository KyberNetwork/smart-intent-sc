// // SPDX-License-Identifier: GPL-3.0-or-later
// pragma solidity ^0.8.0;

// import './Base.t.sol';

// contract MockActionTest is BaseTest {
//   using SafeERC20 for IERC20;

//   uint256 nonce = 0;

//   function testMockActionExecuteSuccess(uint256 seed) public {
//     uint256 mode = bound(seed, 0, 2);
//     IKSSmartIntentRouter.IntentData memory intentData = _getIntentData(seed);
//     bytes32 intentHash = router.hashTypedIntentData(intentData);

//     vm.prank(mainAddress);
//     router.delegate(intentData);
//     _checkAllowancesAfterDelegation(intentHash, intentData.tokenData);

//     IKSSmartIntentRouter.TokenData memory newTokenData =
//       _getNewTokenData(intentData.tokenData, seed);
//     IKSSmartIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

//     vm.warp(block.timestamp + 100);
//     (address caller, bytes memory daSignature, bytes memory gdSignature) =
//       _getCallerAndSignatures(mode, actionData);

//     vm.startPrank(caller);
//     router.execute(intentData, daSignature, guardian, gdSignature, actionData);
//     _checkAllowancesAfterExecution(intentHash, intentData.tokenData, newTokenData);
//   }

//   function testMockActionExecuteWithSignedIntentSuccess(uint256 seed) public {
//     uint256 mode = bound(seed, 0, 2);
//     IKSSmartIntentRouter.IntentData memory intentData = _getIntentData(seed);
//     bytes32 intentHash = router.hashTypedIntentData(intentData);

//     IKSSmartIntentRouter.TokenData memory newTokenData =
//       _getNewTokenData(intentData.tokenData, seed);
//     IKSSmartIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

//     vm.warp(block.timestamp + 100);
//     (address caller, bytes memory daSignature, bytes memory gdSignature) =
//       _getCallerAndSignatures(mode, actionData);

//     bytes memory maSignature = _getMASignature(intentData);
//     vm.startPrank(caller);
//     router.executeWithSignedIntent(
//       intentData, maSignature, daSignature, guardian, gdSignature, actionData
//     );
//     _checkAllowancesAfterExecution(intentHash, intentData.tokenData, newTokenData);
//   }

//   function testMockActionCollectERC1155MoreThanAllowanceShouldRevert(uint256 seed) public {
//     uint256 mode = bound(seed, 0, 2);
//     IKSSmartIntentRouter.IntentData memory intentData = _getIntentData(seed);
//     bytes32 intentHash = router.hashTypedIntentData(intentData);

//     vm.prank(mainAddress);
//     router.delegate(intentData);

//     IKSSmartIntentRouter.TokenData memory newTokenData =
//       _getNewTokenData(intentData.tokenData, seed);
//     newTokenData.erc1155Data[0].amounts[0] =
//       intentData.tokenData.erc1155Data[0].amounts[0] + bound(seed, 1, 1e18);
//     IKSSmartIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

//     vm.warp(block.timestamp + 100);
//     (address caller, bytes memory daSignature, bytes memory gdSignature) =
//       _getCallerAndSignatures(mode, actionData);

//     vm.startPrank(caller);
//     vm.expectRevert(
//       abi.encodeWithSelector(
//         IKSSmartIntentRouter.ERC1155InsufficientIntentAllowance.selector,
//         intentHash,
//         newTokenData.erc1155Data[0].token,
//         newTokenData.erc1155Data[0].tokenIds[0],
//         intentData.tokenData.erc1155Data[0].amounts[0],
//         newTokenData.erc1155Data[0].amounts[0]
//       )
//     );
//     router.execute(intentData, daSignature, guardian, gdSignature, actionData);
//   }

//   function testMockActionCollectERC20MoreThanAllowanceShouldRevert(uint256 seed) public {
//     uint256 mode = bound(seed, 0, 2);
//     IKSSmartIntentRouter.IntentData memory intentData = _getIntentData(seed);
//     bytes32 intentHash = router.hashTypedIntentData(intentData);

//     vm.prank(mainAddress);
//     router.delegate(intentData);

//     IKSSmartIntentRouter.TokenData memory newTokenData =
//       _getNewTokenData(intentData.tokenData, seed);
//     newTokenData.erc20Data[0].amount =
//       intentData.tokenData.erc20Data[0].amount + bound(seed, 1, 1e18);
//     IKSSmartIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

//     vm.warp(block.timestamp + 100);
//     (address caller, bytes memory daSignature, bytes memory gdSignature) =
//       _getCallerAndSignatures(mode, actionData);

//     vm.startPrank(caller);
//     vm.expectRevert(
//       abi.encodeWithSelector(
//         IKSSmartIntentRouter.ERC20InsufficientIntentAllowance.selector,
//         intentHash,
//         newTokenData.erc20Data[0].token,
//         intentData.tokenData.erc20Data[0].amount,
//         newTokenData.erc20Data[0].amount
//       )
//     );
//     router.execute(intentData, daSignature, guardian, gdSignature, actionData);
//   }

//   function testMockActionCollectERC721WithoutApprovalShouldRevert(uint256 seed) public {
//     uint256 mode = bound(seed, 0, 2);
//     IKSSmartIntentRouter.IntentData memory intentData = _getIntentData(seed);
//     bytes32 intentHash = router.hashTypedIntentData(intentData);

//     vm.prank(mainAddress);
//     router.delegate(intentData);

//     IKSSmartIntentRouter.TokenData memory newTokenData =
//       _getNewTokenData(intentData.tokenData, seed);

//     newTokenData.erc721Data[0].tokenId = seed == UINT256_MAX ? seed - 1 : seed + 1; // overflow when seed = 2**256 - 1
//     IKSSmartIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

//     vm.warp(block.timestamp + 100);
//     (address caller, bytes memory daSignature, bytes memory gdSignature) =
//       _getCallerAndSignatures(mode, actionData);

//     vm.startPrank(caller);
//     vm.expectRevert(
//       abi.encodeWithSelector(
//         IKSSmartIntentRouter.ERC721InsufficientIntentApproval.selector,
//         intentHash,
//         newTokenData.erc721Data[0].token,
//         newTokenData.erc721Data[0].tokenId
//       )
//     );
//     router.execute(intentData, daSignature, guardian, gdSignature, actionData);
//   }

//   function testMockActionDelegateWithRandomCallerShouldRevert(uint256 seed) public {
//     IKSSmartIntentRouter.IntentData memory intentData = _getIntentData(seed);

//     vm.prank(randomCaller);
//     vm.expectRevert(IKSSmartIntentRouter.NotMainAddress.selector);
//     router.delegate(intentData);
//   }

//   function testMockActionExecuteWithNonWhitelistedActionShouldRevert(uint256 seed) public {
//     {
//       vm.startPrank(owner);
//       address[] memory actionContracts = new address[](1);
//       actionContracts[0] = address(mockActionContract);
//       bytes4[] memory actionSelectors = new bytes4[](1);
//       actionSelectors[0] = MockActionContract.doNothing.selector;
//       router.whitelistActions(actionContracts, actionSelectors, false);
//       vm.stopPrank();
//     }

//     uint256 mode = bound(seed, 0, 2);
//     IKSSmartIntentRouter.IntentData memory intentData = _getIntentData(seed);

//     IKSSmartIntentRouter.TokenData memory newTokenData =
//       _getNewTokenData(intentData.tokenData, seed);
//     IKSSmartIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

//     vm.warp(block.timestamp + 100);
//     (address caller, bytes memory daSignature, bytes memory gdSignature) =
//       _getCallerAndSignatures(mode, actionData);

//     bytes memory maSignature = _getMASignature(intentData);
//     vm.startPrank(caller);
//     vm.expectRevert(
//       abi.encodeWithSelector(
//         IKSSmartIntentRouter.NonWhitelistedAction.selector,
//         address(mockActionContract),
//         MockActionContract.doNothing.selector
//       )
//     );
//     router.executeWithSignedIntent(
//       intentData, maSignature, daSignature, guardian, gdSignature, actionData
//     );
//   }

//   function testMockActionExecuteWithNonWhitelistedActionAfterDelegateShouldRevert(uint256 seed)
//     public
//   {
//     uint256 mode = bound(seed, 0, 2);
//     IKSSmartIntentRouter.IntentData memory intentData = _getIntentData(seed);

//     vm.prank(mainAddress);
//     router.delegate(intentData);

//     {
//       vm.startPrank(owner);
//       address[] memory actionContracts = new address[](1);
//       actionContracts[0] = address(mockActionContract);
//       bytes4[] memory actionSelectors = new bytes4[](1);
//       actionSelectors[0] = MockActionContract.doNothing.selector;
//       router.whitelistActions(actionContracts, actionSelectors, false);
//       vm.stopPrank();
//     }

//     IKSSmartIntentRouter.TokenData memory newTokenData =
//       _getNewTokenData(intentData.tokenData, seed);
//     IKSSmartIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

//     vm.warp(block.timestamp + 100);
//     (address caller, bytes memory daSignature, bytes memory gdSignature) =
//       _getCallerAndSignatures(mode, actionData);

//     vm.startPrank(caller);
//     vm.expectRevert(
//       abi.encodeWithSelector(
//         IKSSmartIntentRouter.NonWhitelistedAction.selector,
//         address(mockActionContract),
//         MockActionContract.doNothing.selector
//       )
//     );
//     router.execute(intentData, daSignature, guardian, gdSignature, actionData);
//   }

//   function testMockActionExecuteWithNonWhitelistedValidatorShouldRevert(uint256 seed) public {
//     {
//       vm.startPrank(owner);
//       address[] memory validators = new address[](1);
//       validators[0] = address(mockValidator);
//       router.whitelistValidators(validators, false);
//       vm.stopPrank();
//     }

//     uint256 mode = bound(seed, 0, 2);
//     IKSSmartIntentRouter.IntentData memory intentData = _getIntentData(seed);

//     IKSSmartIntentRouter.TokenData memory newTokenData =
//       _getNewTokenData(intentData.tokenData, seed);
//     IKSSmartIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

//     vm.warp(block.timestamp + 100);
//     (address caller, bytes memory daSignature, bytes memory gdSignature) =
//       _getCallerAndSignatures(mode, actionData);

//     bytes memory maSignature = _getMASignature(intentData);
//     vm.startPrank(caller);
//     vm.expectRevert(
//       abi.encodeWithSelector(IKSSmartIntentRouter.NonWhitelistedValidator.selector, mockValidator)
//     );
//     router.executeWithSignedIntent(
//       intentData, maSignature, daSignature, guardian, gdSignature, actionData
//     );
//   }

//   function testMockActionExecuteWithNonWhitelistedValidatorAfterDelegateShouldRevert(uint256 seed)
//     public
//   {
//     uint256 mode = bound(seed, 0, 2);
//     IKSSmartIntentRouter.IntentData memory intentData = _getIntentData(seed);

//     vm.prank(mainAddress);
//     router.delegate(intentData);

//     {
//       vm.startPrank(owner);
//       address[] memory validators = new address[](1);
//       validators[0] = address(mockValidator);
//       router.whitelistValidators(validators, false);
//       vm.stopPrank();
//     }

//     IKSSmartIntentRouter.TokenData memory newTokenData =
//       _getNewTokenData(intentData.tokenData, seed);
//     IKSSmartIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

//     vm.warp(block.timestamp + 100);
//     (address caller, bytes memory daSignature, bytes memory gdSignature) =
//       _getCallerAndSignatures(mode, actionData);

//     vm.startPrank(caller);
//     vm.expectRevert(
//       abi.encodeWithSelector(IKSSmartIntentRouter.NonWhitelistedValidator.selector, mockValidator)
//     );
//     router.execute(intentData, daSignature, guardian, gdSignature, actionData);
//   }

//   function testMockActionRevokeWithRandomCallerShouldRevert(uint256 seed) public {
//     IKSSmartIntentRouter.IntentData memory intentData = _getIntentData(seed);

//     vm.prank(mainAddress);
//     router.delegate(intentData);

//     vm.startPrank(randomCaller);
//     vm.expectRevert(IKSSmartIntentRouter.NotMainAddress.selector);
//     router.revoke(intentData);
//     vm.stopPrank();
//   }

//   function testMockActionExecuteRevokedIntentShouldRevert(uint256 seed) public {
//     uint256 mode = bound(seed, 0, 2);
//     IKSSmartIntentRouter.IntentData memory intentData = _getIntentData(seed);

//     vm.startPrank(mainAddress);
//     router.delegate(intentData);
//     router.revoke(intentData);
//     vm.stopPrank();

//     IKSSmartIntentRouter.TokenData memory newTokenData =
//       _getNewTokenData(intentData.tokenData, seed);
//     IKSSmartIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

//     vm.warp(block.timestamp + 100);
//     (address caller, bytes memory daSignature, bytes memory gdSignature) =
//       _getCallerAndSignatures(mode, actionData);

//     vm.startPrank(caller);
//     vm.expectRevert(IKSSmartIntentRouter.IntentRevoked.selector);
//     router.execute(intentData, daSignature, guardian, gdSignature, actionData);
//   }

//   function testMockActionDelegateRevokedIntentWithIntentDataShouldRevert(uint256 seed) public {
//     IKSSmartIntentRouter.IntentData memory intentData = _getIntentData(seed);

//     vm.startPrank(mainAddress);
//     router.revoke(intentData);
//     vm.expectRevert(IKSSmartIntentRouter.IntentRevoked.selector);
//     router.delegate(intentData);
//     vm.stopPrank();
//   }

//   function testMockActionExecuteRevokedIntentWithIntentDataShouldRevert(uint256 seed) public {
//     uint256 mode = bound(seed, 0, 2);
//     IKSSmartIntentRouter.IntentData memory intentData = _getIntentData(seed);

//     vm.startPrank(mainAddress);
//     router.revoke(intentData);
//     vm.stopPrank();

//     IKSSmartIntentRouter.TokenData memory newTokenData =
//       _getNewTokenData(intentData.tokenData, seed);
//     IKSSmartIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

//     vm.warp(block.timestamp + 100);
//     (address caller, bytes memory daSignature, bytes memory gdSignature) =
//       _getCallerAndSignatures(mode, actionData);

//     vm.startPrank(caller);
//     vm.expectRevert(IKSSmartIntentRouter.IntentRevoked.selector);
//     router.execute(intentData, daSignature, guardian, gdSignature, actionData);
//   }

//   function testMockActionExecuteNOT_DELEGATEDIntentShouldRevert(uint256 seed) public {
//     uint256 mode = bound(seed, 0, 2);
//     IKSSmartIntentRouter.IntentData memory intentData = _getIntentData(seed);

//     IKSSmartIntentRouter.TokenData memory newTokenData =
//       _getNewTokenData(intentData.tokenData, seed);
//     IKSSmartIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

//     vm.warp(block.timestamp + 100);
//     (address caller, bytes memory daSignature, bytes memory gdSignature) =
//       _getCallerAndSignatures(mode, actionData);

//     vm.startPrank(caller);
//     vm.expectRevert();
//     router.execute(intentData, daSignature, guardian, gdSignature, actionData);
//   }

//   function testMockActionDelegateExistedIntentShouldRevert(uint256 seed) public {
//     IKSSmartIntentRouter.IntentData memory intentData = _getIntentData(seed);

//     vm.startPrank(mainAddress);
//     router.delegate(intentData);

//     vm.expectRevert(IKSSmartIntentRouter.IntentDelegated.selector);
//     router.delegate(intentData);
//   }

//   function testMockActionExecuteEmptyActionShouldRevert(uint256 seed) public {
//     uint256 mode = bound(seed, 0, 2);
//     IKSSmartIntentRouter.IntentData memory intentData = _getIntentData(seed);
//     intentData.coreData.actionContracts = new address[](0);
//     intentData.coreData.actionSelectors = new bytes4[](0);

//     bytes32 intentHash = router.hashTypedIntentData(intentData);

//     vm.prank(mainAddress);
//     router.delegate(intentData);
//     _checkAllowancesAfterDelegation(intentHash, intentData.tokenData);

//     IKSSmartIntentRouter.TokenData memory newTokenData =
//       _getNewTokenData(intentData.tokenData, seed);
//     IKSSmartIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

//     vm.warp(block.timestamp + 100);
//     (address caller, bytes memory daSignature, bytes memory gdSignature) =
//       _getCallerAndSignatures(mode, actionData);

//     vm.startPrank(caller);
//     vm.expectRevert(
//       abi.encodeWithSelector(IKSSmartIntentRouter.InvalidActionSelectorId.selector, 0)
//     );
//     router.execute(intentData, daSignature, guardian, gdSignature, actionData);
//   }

//   function testMockActionExecuteActionNotInListActionsShouldRevert(uint256 seed) public {
//     uint256 mode = bound(seed, 0, 2);
//     IKSSmartIntentRouter.IntentData memory intentData = _getIntentData(seed);
//     bytes32 intentHash = router.hashTypedIntentData(intentData);

//     vm.prank(mainAddress);
//     router.delegate(intentData);
//     _checkAllowancesAfterDelegation(intentHash, intentData.tokenData);

//     IKSSmartIntentRouter.TokenData memory newTokenData =
//       _getNewTokenData(intentData.tokenData, seed);
//     IKSSmartIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');
//     actionData.actionSelectorId = 1; // set to 1 to make sure the action is not in the list

//     vm.warp(block.timestamp + 100);
//     (address caller, bytes memory daSignature, bytes memory gdSignature) =
//       _getCallerAndSignatures(mode, actionData);

//     vm.startPrank(caller);
//     vm.expectRevert(
//       abi.encodeWithSelector(IKSSmartIntentRouter.InvalidActionSelectorId.selector, 1)
//     );
//     router.execute(intentData, daSignature, guardian, gdSignature, actionData);
//   }

//   function testMockActionExecuteDifferentActions(uint256 seed) public {
//     uint256 mode = bound(seed, 0, 2);
//     IKSSmartIntentRouter.IntentData memory intentData = _getIntentData(seed);

//     //add actions to intent
//     intentData.coreData.actionContracts = new address[](2);
//     intentData.coreData.actionContracts[0] = address(mockActionContract);
//     intentData.coreData.actionContracts[1] = address(mockDex);

//     intentData.coreData.actionSelectors = new bytes4[](2);
//     intentData.coreData.actionSelectors[0] = MockActionContract.doNothing.selector;
//     intentData.coreData.actionSelectors[1] = MockDex.mockSwap.selector;

//     bytes32 intentHash = router.hashTypedIntentData(intentData);

//     vm.prank(mainAddress);
//     router.delegate(intentData);
//     _checkAllowancesAfterDelegation(intentHash, intentData.tokenData);

//     IKSSmartIntentRouter.TokenData memory newTokenData =
//       _getNewTokenData(intentData.tokenData, seed);
//     IKSSmartIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');
//     actionData.actionSelectorId = 0;

//     vm.warp(block.timestamp + 100);
//     (address caller, bytes memory daSignature, bytes memory gdSignature) =
//       _getCallerAndSignatures(mode, actionData);

//     //execute first time
//     vm.prank(caller);
//     router.execute(intentData, daSignature, guardian, gdSignature, actionData);

//     amountIn = newTokenData.erc20Data[0].amount;

//     newTokenData.erc1155Data = new IKSSmartIntentRouter.ERC1155Data[](0);
//     newTokenData.erc20Data = new IKSSmartIntentRouter.ERC20Data[](1);
//     newTokenData.erc20Data[0] = IKSSmartIntentRouter.ERC20Data({
//       token: address(erc20Mock),
//       amount: newTokenData.erc20Data[0].amount,
//       permitData: ''
//     });
//     newTokenData.erc721Data = new IKSSmartIntentRouter.ERC721Data[](0);

//     actionData.actionSelectorId = 1;
//     actionData.actionCalldata = abi.encode(address(erc20Mock), tokenOut, recipient, amountIn);
//     actionData.nonce = nonce++;

//     vm.warp(block.timestamp + 200);
//     (caller, daSignature, gdSignature) = _getCallerAndSignatures(mode, actionData);

//     //execute second time
//     vm.prank(caller);
//     router.execute(intentData, daSignature, guardian, gdSignature, actionData);
//   }

//   function testMockActionExecuteSuccessShouldEmitExtraData(uint256 seed) public {
//     uint256 mode = bound(seed, 0, 2);
//     IKSSmartIntentRouter.IntentData memory intentData = _getIntentData(seed);
//     bytes32 intentHash = router.hashTypedIntentData(intentData);

//     vm.prank(mainAddress);
//     router.delegate(intentData);
//     _checkAllowancesAfterDelegation(intentHash, intentData.tokenData);

//     IKSSmartIntentRouter.TokenData memory newTokenData =
//       _getNewTokenData(intentData.tokenData, seed);
//     IKSSmartIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');
//     actionData.extraData = hex'1234';

//     vm.warp(block.timestamp + 100);
//     (address caller, bytes memory daSignature, bytes memory gdSignature) =
//       _getCallerAndSignatures(mode, actionData);

//     vm.recordLogs();
//     vm.startPrank(caller);
//     router.execute(intentData, daSignature, guardian, gdSignature, actionData);
//     _checkAllowancesAfterExecution(intentHash, intentData.tokenData, newTokenData);

//     Vm.Log[] memory entries = vm.getRecordedLogs();

//     for (uint256 i; i < entries.length; i++) {
//       if (
//         entries[i].topics[0]
//           == keccak256(
//             'ExecuteIntent(bytes32,(((address,uint256[],uint256[])[],(address,uint256)[],(address,uint256)[]),uint256,bytes,bytes,bytes,uint256),bytes)'
//           )
//       ) {
//         assertEq(entries[i].topics[1], intentHash);
//         assertEq(entries[i].data, abi.encode(actionData, new bytes(0)));
//       }
//     }
//   }

//   function testMockActionExecuteWithSameNonceShouldRevert(uint256 seed) public {
//     uint256 mode = bound(seed, 0, 2);
//     IKSSmartIntentRouter.IntentData memory intentData = _getIntentData(seed);
//     bytes32 intentHash = router.hashTypedIntentData(intentData);

//     vm.prank(mainAddress);
//     router.delegate(intentData);
//     _checkAllowancesAfterDelegation(intentHash, intentData.tokenData);

//     IKSSmartIntentRouter.TokenData memory newTokenData =
//       _getNewTokenData(intentData.tokenData, seed);
//     IKSSmartIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');
//     actionData.nonce = seed;

//     vm.warp(block.timestamp + 100);
//     (address caller, bytes memory daSignature, bytes memory gdSignature) =
//       _getCallerAndSignatures(mode, actionData);

//     vm.startPrank(caller);
//     router.execute(intentData, daSignature, guardian, gdSignature, actionData);
//     _checkAllowancesAfterExecution(intentHash, intentData.tokenData, newTokenData);

//     vm.expectRevert(
//       abi.encodeWithSelector(
//         IKSSmartIntentRouter.NonceAlreadyUsed.selector, intentHash, actionData.nonce
//       )
//     );
//     router.execute(intentData, daSignature, guardian, gdSignature, actionData);
//   }

//   function _getNewTokenData(IKSSmartIntentRouter.TokenData memory tokenData, uint256 seed)
//     internal
//     view
//     returns (IKSSmartIntentRouter.TokenData memory newTokenData)
//   {
//     uint256 size = bound(seed, 1, 10);

//     newTokenData.erc1155Data = new IKSSmartIntentRouter.ERC1155Data[](1);
//     newTokenData.erc1155Data[0].token = address(erc1155Mock);
//     newTokenData.erc1155Data[0].tokenIds = new uint256[](size);
//     newTokenData.erc1155Data[0].amounts = new uint256[](size);
//     for (uint256 i = 0; i < size; i++) {
//       newTokenData.erc1155Data[0].tokenIds[i] = i;
//       newTokenData.erc1155Data[0].amounts[i] = bound(seed, 1, tokenData.erc1155Data[0].amounts[i]);
//     }

//     newTokenData.erc20Data = new IKSSmartIntentRouter.ERC20Data[](1);
//     newTokenData.erc20Data[0] = IKSSmartIntentRouter.ERC20Data({
//       token: address(erc20Mock),
//       amount: bound(seed, 1, tokenData.erc20Data[0].amount),
//       permitData: ''
//     });

//     newTokenData.erc721Data = new IKSSmartIntentRouter.ERC721Data[](1);
//     newTokenData.erc721Data[0] =
//       IKSSmartIntentRouter.ERC721Data({token: address(erc721Mock), tokenId: seed, permitData: ''});
//   }

//   function _getIntentData(uint256 seed)
//     internal
//     returns (IKSSmartIntentRouter.IntentData memory intentData)
//   {
//     vm.startPrank(mainAddress);
//     IKSSmartIntentRouter.IntentCoreData memory coreData = IKSSmartIntentRouter.IntentCoreData({
//       mainAddress: mainAddress,
//       delegatedAddress: delegatedAddress,
//       actionContracts: _toArray(address(mockActionContract)),
//       actionSelectors: _toArray(MockActionContract.doNothing.selector),
//       validator: address(mockValidator),
//       validationData: ''
//     });

//     IKSSmartIntentRouter.TokenData memory tokenData;

//     uint256 size = bound(seed, 1, 10);

//     tokenData.erc1155Data = new IKSSmartIntentRouter.ERC1155Data[](1);
//     tokenData.erc1155Data[0].token = address(erc1155Mock);
//     tokenData.erc1155Data[0].tokenIds = new uint256[](size);
//     tokenData.erc1155Data[0].amounts = new uint256[](size);
//     for (uint256 i = 0; i < size; i++) {
//       tokenData.erc1155Data[0].tokenIds[i] = i;
//       tokenData.erc1155Data[0].amounts[i] = bound(seed / (i + 1), 1, 1e18);
//       erc1155Mock.mint(mainAddress, i, tokenData.erc1155Data[0].amounts[i]);
//     }
//     erc1155Mock.setApprovalForAll(address(router), true);

//     tokenData.erc20Data = new IKSSmartIntentRouter.ERC20Data[](1);
//     tokenData.erc20Data[0] = IKSSmartIntentRouter.ERC20Data({
//       token: address(erc20Mock),
//       amount: bound(seed, 1, 1e18),
//       permitData: ''
//     });
//     erc20Mock.mint(mainAddress, tokenData.erc20Data[0].amount);
//     erc20Mock.approve(address(router), tokenData.erc20Data[0].amount);

//     tokenData.erc721Data = new IKSSmartIntentRouter.ERC721Data[](1);
//     tokenData.erc721Data[0] =
//       IKSSmartIntentRouter.ERC721Data({token: address(erc721Mock), tokenId: seed, permitData: ''});
//     erc721Mock.mint(mainAddress, seed);
//     erc721Mock.approve(address(router), seed);

//     intentData =
//       IKSSmartIntentRouter.IntentData({coreData: coreData, tokenData: tokenData, extraData: ''});
//     vm.stopPrank();
//   }

//   function _getActionData(
//     IKSSmartIntentRouter.TokenData memory tokenData,
//     bytes memory actionCalldata
//   ) internal returns (IKSSmartIntentRouter.ActionData memory actionData) {
//     actionData = IKSSmartIntentRouter.ActionData({
//       tokenData: tokenData,
//       actionSelectorId: 0,
//       actionCalldata: actionCalldata,
//       validatorData: '',
//       extraData: '',
//       deadline: block.timestamp + 1 days,
//       nonce: nonce++
//     });
//   }

//   function _checkAllowancesAfterDelegation(
//     bytes32 intentHash,
//     IKSSmartIntentRouter.TokenData memory tokenData
//   ) internal view {
//     for (uint256 i = 0; i < tokenData.erc1155Data.length; i++) {
//       IKSSmartIntentRouter.ERC1155Data memory erc1155Data = tokenData.erc1155Data[i];
//       for (uint256 j = 0; j < erc1155Data.tokenIds.length; j++) {
//         assertEq(
//           router.erc1155Allowances(intentHash, erc1155Data.token, erc1155Data.tokenIds[j]),
//           erc1155Data.amounts[j],
//           'ERC1155 allowance not set correctly after delegation'
//         );
//       }
//     }
//     for (uint256 i = 0; i < tokenData.erc20Data.length; i++) {
//       IKSSmartIntentRouter.ERC20Data memory erc20Data = tokenData.erc20Data[i];
//       assertEq(
//         router.erc20Allowances(intentHash, erc20Data.token),
//         erc20Data.amount,
//         'ERC20 allowance not set correctly after delegation'
//       );
//     }
//     for (uint256 i = 0; i < tokenData.erc721Data.length; i++) {
//       IKSSmartIntentRouter.ERC721Data memory erc721Data = tokenData.erc721Data[i];
//       assertTrue(
//         router.erc721Approvals(intentHash, erc721Data.token, erc721Data.tokenId),
//         'ERC721 approval not set correctly after delegation'
//       );
//     }
//   }

//   function _checkAllowancesAfterExecution(
//     bytes32 intentHash,
//     IKSSmartIntentRouter.TokenData memory tokenData,
//     IKSSmartIntentRouter.TokenData memory newTokenData
//   ) internal view {
//     for (uint256 i = 0; i < tokenData.erc1155Data.length; i++) {
//       IKSSmartIntentRouter.ERC1155Data memory erc1155Data = tokenData.erc1155Data[i];
//       for (uint256 j = 0; j < erc1155Data.tokenIds.length; j++) {
//         assertEq(
//           router.erc1155Allowances(intentHash, erc1155Data.token, erc1155Data.tokenIds[j]),
//           erc1155Data.amounts[j] - newTokenData.erc1155Data[i].amounts[j],
//           'ERC1155 allowance not updated correctly after execution'
//         );
//       }
//     }
//     for (uint256 i = 0; i < tokenData.erc20Data.length; i++) {
//       IKSSmartIntentRouter.ERC20Data memory erc20Data = tokenData.erc20Data[i];
//       assertEq(
//         router.erc20Allowances(intentHash, erc20Data.token),
//         erc20Data.amount - newTokenData.erc20Data[i].amount,
//         'ERC20 allowance not updated correctly after execution'
//       );
//     }
//   }
// }
