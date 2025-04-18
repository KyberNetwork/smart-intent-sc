// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.t.sol';

contract MockActionTest is BaseTest {
  using SafeERC20 for IERC20;

  function testMockActionExecuteSuccess(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    vm.prank(mainAddress);
    router.delegate(intentData);
    _checkAllowancesAfterDelegation(intentHash, intentData.tokenData);

    IKSSessionIntentRouter.TokenData memory newTokenData =
      _getNewTokenData(intentData.tokenData, seed);
    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    vm.startPrank(caller);
    router.execute(intentHash, daSignature, guardian, gdSignature, actionData);
    _checkAllowancesAfterExecution(intentHash, intentData.tokenData, newTokenData);
  }

  function testMockActionExecuteWithSignedIntentSuccess(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    IKSSessionIntentRouter.TokenData memory newTokenData =
      _getNewTokenData(intentData.tokenData, seed);
    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    bytes memory maSignature = _getMASignature(intentData);
    vm.startPrank(caller);
    router.executeWithSignedIntent(
      intentData, maSignature, daSignature, guardian, gdSignature, actionData
    );
    _checkAllowancesAfterExecution(intentHash, intentData.tokenData, newTokenData);
  }

  function testMockActionCollectERC1155MoreThanAllowanceShouldRevert(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    vm.prank(mainAddress);
    router.delegate(intentData);

    IKSSessionIntentRouter.TokenData memory newTokenData =
      _getNewTokenData(intentData.tokenData, seed);
    newTokenData.erc1155Data[0].amounts[0] =
      intentData.tokenData.erc1155Data[0].amounts[0] + bound(seed, 1, 1e18);
    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        IKSSessionIntentRouter.ERC1155InsufficientIntentAllowance.selector,
        intentHash,
        newTokenData.erc1155Data[0].token,
        newTokenData.erc1155Data[0].tokenIds[0],
        intentData.tokenData.erc1155Data[0].amounts[0],
        newTokenData.erc1155Data[0].amounts[0]
      )
    );
    router.execute(intentHash, daSignature, guardian, gdSignature, actionData);
  }

  function testMockActionCollectERC20MoreThanAllowanceShouldRevert(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    vm.prank(mainAddress);
    router.delegate(intentData);

    IKSSessionIntentRouter.TokenData memory newTokenData =
      _getNewTokenData(intentData.tokenData, seed);
    newTokenData.erc20Data[0].amount =
      intentData.tokenData.erc20Data[0].amount + bound(seed, 1, 1e18);
    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        IKSSessionIntentRouter.ERC20InsufficientIntentAllowance.selector,
        intentHash,
        newTokenData.erc20Data[0].token,
        intentData.tokenData.erc20Data[0].amount,
        newTokenData.erc20Data[0].amount
      )
    );
    router.execute(intentHash, daSignature, guardian, gdSignature, actionData);
  }

  function testMockActionCollectERC721WithoutApprovalShouldRevert(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    vm.prank(mainAddress);
    router.delegate(intentData);

    IKSSessionIntentRouter.TokenData memory newTokenData =
      _getNewTokenData(intentData.tokenData, seed);
    newTokenData.erc721Data[0].tokenId = seed + 1;
    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        IKSSessionIntentRouter.ERC721InsufficientIntentApproval.selector,
        intentHash,
        newTokenData.erc721Data[0].token,
        newTokenData.erc721Data[0].tokenId
      )
    );
    router.execute(intentHash, daSignature, guardian, gdSignature, actionData);
  }

  function testMockActionDelegateWithRandomCallerShouldRevert(uint256 seed) public {
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);

    vm.prank(randomCaller);
    vm.expectRevert(IKSSessionIntentRouter.NotMainAddress.selector);
    router.delegate(intentData);
  }

  function testMockActionDelegateWithNonWhitelistedActionShouldRevert(uint256 seed) public {
    {
      vm.startPrank(owner);
      address[] memory actionContracts = new address[](1);
      actionContracts[0] = address(mockActionContract);
      bytes4[] memory actionSelectors = new bytes4[](1);
      actionSelectors[0] = MockActionContract.doNothing.selector;
      router.whitelistActions(actionContracts, actionSelectors, false);
      vm.stopPrank();
    }

    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);

    vm.startPrank(mainAddress);
    vm.expectRevert(
      abi.encodeWithSelector(
        IKSSessionIntentRouter.NonWhitelistedAction.selector,
        address(mockActionContract),
        MockActionContract.doNothing.selector
      )
    );
    router.delegate(intentData);
  }

  function testMockActionDelegateWithNonWhitelistedValidatorShouldRevert(uint256 seed) public {
    {
      vm.startPrank(owner);
      address[] memory validators = new address[](1);
      validators[0] = address(mockValidator);
      router.whitelistValidators(validators, false);
      vm.stopPrank();
    }

    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);

    vm.startPrank(mainAddress);
    vm.expectRevert(
      abi.encodeWithSelector(IKSSessionIntentRouter.NonWhitelistedValidator.selector, mockValidator)
    );
    router.delegate(intentData);
  }

  function testMockActionExecuteWithNonWhitelistedActionShouldRevert(uint256 seed) public {
    {
      vm.startPrank(owner);
      address[] memory actionContracts = new address[](1);
      actionContracts[0] = address(mockActionContract);
      bytes4[] memory actionSelectors = new bytes4[](1);
      actionSelectors[0] = MockActionContract.doNothing.selector;
      router.whitelistActions(actionContracts, actionSelectors, false);
      vm.stopPrank();
    }

    uint256 mode = bound(seed, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);

    IKSSessionIntentRouter.TokenData memory newTokenData =
      _getNewTokenData(intentData.tokenData, seed);
    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    bytes memory maSignature = _getMASignature(intentData);
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        IKSSessionIntentRouter.NonWhitelistedAction.selector,
        address(mockActionContract),
        MockActionContract.doNothing.selector
      )
    );
    router.executeWithSignedIntent(
      intentData, maSignature, daSignature, guardian, gdSignature, actionData
    );
  }

  function testMockActionExecuteWithNonWhitelistedActionAfterDelegateShouldRevert(uint256 seed)
    public
  {
    uint256 mode = bound(seed, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    vm.prank(mainAddress);
    router.delegate(intentData);

    {
      vm.startPrank(owner);
      address[] memory actionContracts = new address[](1);
      actionContracts[0] = address(mockActionContract);
      bytes4[] memory actionSelectors = new bytes4[](1);
      actionSelectors[0] = MockActionContract.doNothing.selector;
      router.whitelistActions(actionContracts, actionSelectors, false);
      vm.stopPrank();
    }

    IKSSessionIntentRouter.TokenData memory newTokenData =
      _getNewTokenData(intentData.tokenData, seed);
    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        IKSSessionIntentRouter.NonWhitelistedAction.selector,
        address(mockActionContract),
        MockActionContract.doNothing.selector
      )
    );
    router.execute(intentHash, daSignature, guardian, gdSignature, actionData);
  }

  function testMockActionExecuteWithNonWhitelistedValidatorShouldRevert(uint256 seed) public {
    {
      vm.startPrank(owner);
      address[] memory validators = new address[](1);
      validators[0] = address(mockValidator);
      router.whitelistValidators(validators, false);
      vm.stopPrank();
    }

    uint256 mode = bound(seed, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);

    IKSSessionIntentRouter.TokenData memory newTokenData =
      _getNewTokenData(intentData.tokenData, seed);
    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    bytes memory maSignature = _getMASignature(intentData);
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IKSSessionIntentRouter.NonWhitelistedValidator.selector, mockValidator)
    );
    router.executeWithSignedIntent(
      intentData, maSignature, daSignature, guardian, gdSignature, actionData
    );
  }

  function testMockActionExecuteWithNonWhitelistedValidatorAfterDelegateShouldRevert(uint256 seed)
    public
  {
    uint256 mode = bound(seed, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    vm.prank(mainAddress);
    router.delegate(intentData);

    {
      vm.startPrank(owner);
      address[] memory validators = new address[](1);
      validators[0] = address(mockValidator);
      router.whitelistValidators(validators, false);
      vm.stopPrank();
    }

    IKSSessionIntentRouter.TokenData memory newTokenData =
      _getNewTokenData(intentData.tokenData, seed);
    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IKSSessionIntentRouter.NonWhitelistedValidator.selector, mockValidator)
    );
    router.execute(intentHash, daSignature, guardian, gdSignature, actionData);
  }

  function testMockActionRevokeWithRandomCallerShouldRevert(uint256 seed) public {
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    vm.prank(mainAddress);
    router.delegate(intentData);

    vm.startPrank(randomCaller);
    vm.expectRevert(IKSSessionIntentRouter.NotMainAddress.selector);
    router.revoke(intentHash);
    vm.stopPrank();
  }

  function testMockActionExecuteRevokedIntentShouldRevert(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    vm.startPrank(mainAddress);
    router.delegate(intentData);
    router.revoke(intentHash);
    vm.stopPrank();

    IKSSessionIntentRouter.TokenData memory newTokenData =
      _getNewTokenData(intentData.tokenData, seed);
    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    vm.startPrank(caller);
    vm.expectRevert(IKSSessionIntentRouter.IntentRevoked.selector);
    router.execute(intentHash, daSignature, guardian, gdSignature, actionData);
  }

  function testMockActionDelegateRevokedIntentWithIntentDataShouldRevert(uint256 seed) public {
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);

    vm.startPrank(mainAddress);
    router.revoke(intentData);
    vm.expectRevert(IKSSessionIntentRouter.IntentAlreadyExistsOrRevoked.selector);
    router.delegate(intentData);
    vm.stopPrank();
  }

  function testMockActionExecuteRevokedIntentWithIntentDataShouldRevert(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    vm.startPrank(mainAddress);
    router.revoke(intentData);
    vm.stopPrank();

    IKSSessionIntentRouter.TokenData memory newTokenData =
      _getNewTokenData(intentData.tokenData, seed);
    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    vm.startPrank(caller);
    vm.expectRevert(IKSSessionIntentRouter.IntentRevoked.selector);
    router.execute(intentHash, daSignature, guardian, gdSignature, actionData);
  }

  function testMockActionExecuteNonExistentIntentShouldRevert(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    IKSSessionIntentRouter.TokenData memory newTokenData =
      _getNewTokenData(intentData.tokenData, seed);
    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    vm.startPrank(caller);
    vm.expectRevert();
    router.execute(intentHash, daSignature, guardian, gdSignature, actionData);
  }

  function testMockActionDelegateExistedIntentShouldRevert(uint256 seed) public {
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);

    vm.startPrank(mainAddress);
    router.delegate(intentData);

    vm.expectRevert(IKSSessionIntentRouter.IntentAlreadyExistsOrRevoked.selector);
    router.delegate(intentData);
  }

  function testMockActionExecuteTooLateShouldRevert(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    vm.prank(mainAddress);
    router.delegate(intentData);

    IKSSessionIntentRouter.TokenData memory newTokenData =
      _getNewTokenData(intentData.tokenData, seed);
    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

    vm.warp(intentData.coreData.endTime + 1);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    vm.startPrank(caller);
    vm.expectRevert(IKSSessionIntentRouter.ExecuteTooLate.selector);
    router.execute(intentHash, daSignature, guardian, gdSignature, actionData);
  }

  function testMockActionExecuteTooEarlyShouldRevert(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    vm.prank(mainAddress);
    router.delegate(intentData);

    IKSSessionIntentRouter.TokenData memory newTokenData =
      _getNewTokenData(intentData.tokenData, seed);
    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

    vm.warp(intentData.coreData.startTime - 1);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    vm.startPrank(caller);
    vm.expectRevert(IKSSessionIntentRouter.ExecuteTooEarly.selector);
    router.execute(intentHash, daSignature, guardian, gdSignature, actionData);
  }

  function testMockActionExecuteEmptyActionShouldRevert(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);
    intentData.coreData.actionContracts = new address[](0);
    intentData.coreData.actionSelectors = new bytes4[](0);

    bytes32 intentHash = router.hashTypedIntentData(intentData);

    vm.prank(mainAddress);
    router.delegate(intentData);
    _checkAllowancesAfterDelegation(intentHash, intentData.tokenData);

    IKSSessionIntentRouter.TokenData memory newTokenData =
      _getNewTokenData(intentData.tokenData, seed);
    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        IKSSessionIntentRouter.ActionNotFound.selector,
        address(mockActionContract),
        MockActionContract.doNothing.selector
      )
    );
    router.execute(intentHash, daSignature, guardian, gdSignature, actionData);
  }

  function testMockActionExecuteActionNotInListActionsShouldRevert(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    vm.prank(mainAddress);
    router.delegate(intentData);
    _checkAllowancesAfterDelegation(intentHash, intentData.tokenData);

    IKSSessionIntentRouter.TokenData memory newTokenData =
      _getNewTokenData(intentData.tokenData, seed);
    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');
    actionData.actionContract = address(swapRouter);
    actionData.actionSelector = IKSSwapRouter.swap.selector;

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory daSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, actionData);

    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        IKSSessionIntentRouter.ActionNotFound.selector,
        address(swapRouter),
        IKSSwapRouter.swap.selector
      )
    );
    router.execute(intentHash, daSignature, guardian, gdSignature, actionData);
  }

  function _getNewTokenData(IKSSessionIntentRouter.TokenData memory tokenData, uint256 seed)
    internal
    view
    returns (IKSSessionIntentRouter.TokenData memory newTokenData)
  {
    uint256 size = bound(seed, 1, 10);

    newTokenData.erc1155Data = new IKSSessionIntentRouter.ERC1155Data[](1);
    newTokenData.erc1155Data[0].token = address(erc1155Mock);
    newTokenData.erc1155Data[0].tokenIds = new uint256[](size);
    newTokenData.erc1155Data[0].amounts = new uint256[](size);
    for (uint256 i = 0; i < size; i++) {
      newTokenData.erc1155Data[0].tokenIds[i] = i;
      newTokenData.erc1155Data[0].amounts[i] = bound(seed, 1, tokenData.erc1155Data[0].amounts[i]);
    }

    newTokenData.erc20Data = new IKSSessionIntentRouter.ERC20Data[](1);
    newTokenData.erc20Data[0] = IKSSessionIntentRouter.ERC20Data({
      token: address(erc20Mock),
      amount: bound(seed, 1, tokenData.erc20Data[0].amount)
    });

    newTokenData.erc721Data = new IKSSessionIntentRouter.ERC721Data[](1);
    newTokenData.erc721Data[0] =
      IKSSessionIntentRouter.ERC721Data({token: address(erc721Mock), tokenId: seed});
  }

  function _getIntentData(uint256 seed)
    internal
    returns (IKSSessionIntentRouter.IntentData memory intentData)
  {
    vm.startPrank(mainAddress);
    IKSSessionIntentRouter.IntentCoreData memory coreData = IKSSessionIntentRouter.IntentCoreData({
      mainAddress: mainAddress,
      delegatedAddress: delegatedAddress,
      startTime: block.timestamp + 10,
      endTime: block.timestamp + 1 days,
      actionContracts: _toArray(address(mockActionContract)),
      actionSelectors: _toArray(MockActionContract.doNothing.selector),
      validator: address(mockValidator),
      validationData: ''
    });

    IKSSessionIntentRouter.TokenData memory tokenData;

    uint256 size = bound(seed, 1, 10);

    tokenData.erc1155Data = new IKSSessionIntentRouter.ERC1155Data[](1);
    tokenData.erc1155Data[0].token = address(erc1155Mock);
    tokenData.erc1155Data[0].tokenIds = new uint256[](size);
    tokenData.erc1155Data[0].amounts = new uint256[](size);
    for (uint256 i = 0; i < size; i++) {
      tokenData.erc1155Data[0].tokenIds[i] = i;
      tokenData.erc1155Data[0].amounts[i] = bound(seed / (i + 1), 1, 1e18);
      erc1155Mock.mint(mainAddress, i, tokenData.erc1155Data[0].amounts[i]);
    }
    erc1155Mock.setApprovalForAll(address(router), true);

    tokenData.erc20Data = new IKSSessionIntentRouter.ERC20Data[](1);
    tokenData.erc20Data[0] =
      IKSSessionIntentRouter.ERC20Data({token: address(erc20Mock), amount: bound(seed, 1, 1e18)});
    erc20Mock.mint(mainAddress, tokenData.erc20Data[0].amount);
    erc20Mock.approve(address(router), tokenData.erc20Data[0].amount);

    tokenData.erc721Data = new IKSSessionIntentRouter.ERC721Data[](1);
    tokenData.erc721Data[0] =
      IKSSessionIntentRouter.ERC721Data({token: address(erc721Mock), tokenId: seed});
    erc721Mock.mint(mainAddress, seed);
    erc721Mock.approve(address(router), seed);

    intentData = IKSSessionIntentRouter.IntentData({coreData: coreData, tokenData: tokenData});
    vm.stopPrank();
  }

  function _getActionData(
    IKSSessionIntentRouter.TokenData memory tokenData,
    bytes memory actionCalldata
  ) internal view returns (IKSSessionIntentRouter.ActionData memory actionData) {
    actionData = IKSSessionIntentRouter.ActionData({
      tokenData: tokenData,
      actionContract: address(mockActionContract),
      actionSelector: MockActionContract.doNothing.selector,
      actionCalldata: actionCalldata,
      validatorData: '',
      deadline: block.timestamp + 1 days
    });
  }

  function _checkAllowancesAfterDelegation(
    bytes32 intentHash,
    IKSSessionIntentRouter.TokenData memory tokenData
  ) internal view {
    for (uint256 i = 0; i < tokenData.erc1155Data.length; i++) {
      IKSSessionIntentRouter.ERC1155Data memory erc1155Data = tokenData.erc1155Data[i];
      for (uint256 j = 0; j < erc1155Data.tokenIds.length; j++) {
        assertEq(
          router.getERC1155Allowance(intentHash, erc1155Data.token, erc1155Data.tokenIds[j]),
          erc1155Data.amounts[j],
          'ERC1155 allowance not set correctly after delegation'
        );
      }
    }
    for (uint256 i = 0; i < tokenData.erc20Data.length; i++) {
      IKSSessionIntentRouter.ERC20Data memory erc20Data = tokenData.erc20Data[i];
      assertEq(
        router.getERC20Allowance(intentHash, erc20Data.token),
        erc20Data.amount,
        'ERC20 allowance not set correctly after delegation'
      );
    }
    for (uint256 i = 0; i < tokenData.erc721Data.length; i++) {
      IKSSessionIntentRouter.ERC721Data memory erc721Data = tokenData.erc721Data[i];
      assertTrue(
        router.getERC721Approval(intentHash, erc721Data.token, erc721Data.tokenId),
        'ERC721 approval not set correctly after delegation'
      );
    }
  }

  function _checkAllowancesAfterExecution(
    bytes32 intentHash,
    IKSSessionIntentRouter.TokenData memory tokenData,
    IKSSessionIntentRouter.TokenData memory newTokenData
  ) internal view {
    for (uint256 i = 0; i < tokenData.erc1155Data.length; i++) {
      IKSSessionIntentRouter.ERC1155Data memory erc1155Data = tokenData.erc1155Data[i];
      for (uint256 j = 0; j < erc1155Data.tokenIds.length; j++) {
        assertEq(
          router.getERC1155Allowance(intentHash, erc1155Data.token, erc1155Data.tokenIds[j]),
          erc1155Data.amounts[j] - newTokenData.erc1155Data[i].amounts[j],
          'ERC1155 allowance not updated correctly after execution'
        );
      }
    }
    for (uint256 i = 0; i < tokenData.erc20Data.length; i++) {
      IKSSessionIntentRouter.ERC20Data memory erc20Data = tokenData.erc20Data[i];
      assertEq(
        router.getERC20Allowance(intentHash, erc20Data.token),
        erc20Data.amount - newTokenData.erc20Data[i].amount,
        'ERC20 allowance not updated correctly after execution'
      );
    }
  }
}
