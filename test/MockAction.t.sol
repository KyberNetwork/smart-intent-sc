// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.t.sol';

contract MockActionTest is BaseTest {
  using SafeERC20 for IERC20;

  function testMockActionSuccess(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    _setUpMainWallet(intentData, false);
    _checkAllowancesAfterDelegation(intentHash, intentData.tokenData);

    IKSSessionIntentRouter.TokenData memory newTokenData =
      _getNewTokenData(intentData.tokenData, seed);
    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory swSignature, bytes memory opSignature) =
      _getCallerAndSignatures(mode, actionData);

    vm.startPrank(caller);
    router.execute(intentHash, swSignature, operator, opSignature, actionData);
    _checkAllowancesAfterExecution(intentHash, intentData.tokenData, newTokenData);
  }

  function testMockActionWithSignedIntentSuccess(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    _setUpMainWallet(intentData, true);

    IKSSessionIntentRouter.TokenData memory newTokenData =
      _getNewTokenData(intentData.tokenData, seed);
    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory swSignature, bytes memory opSignature) =
      _getCallerAndSignatures(mode, actionData);

    bytes memory mwSignature = _getMWSignature(intentData);
    vm.startPrank(caller);
    router.executeWithSignedIntent(
      intentData, mwSignature, swSignature, operator, opSignature, actionData
    );
    _checkAllowancesAfterExecution(intentHash, intentData.tokenData, newTokenData);
  }

  function testMockActionSpendERC1155MoreThanAllowanceShouldRevert(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    _setUpMainWallet(intentData, false);

    IKSSessionIntentRouter.TokenData memory newTokenData =
      _getNewTokenData(intentData.tokenData, seed);
    newTokenData.erc1155Data[0].amounts[0] =
      intentData.tokenData.erc1155Data[0].amounts[0] + bound(seed, 1, 1e18);
    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory swSignature, bytes memory opSignature) =
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
    router.execute(intentHash, swSignature, operator, opSignature, actionData);
  }

  function testMockActionSpendERC20MoreThanAllowanceShouldRevert(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    _setUpMainWallet(intentData, false);

    IKSSessionIntentRouter.TokenData memory newTokenData =
      _getNewTokenData(intentData.tokenData, seed);
    newTokenData.erc20Data[0].amount =
      intentData.tokenData.erc20Data[0].amount + bound(seed, 1, 1e18);
    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory swSignature, bytes memory opSignature) =
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
    router.execute(intentHash, swSignature, operator, opSignature, actionData);
  }

  function testMockActionSpendERC721WithoutApprovalShouldRevert(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    _setUpMainWallet(intentData, false);

    IKSSessionIntentRouter.TokenData memory newTokenData =
      _getNewTokenData(intentData.tokenData, seed);
    newTokenData.erc721Data[0].tokenId = seed + 1;
    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory swSignature, bytes memory opSignature) =
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
    router.execute(intentHash, swSignature, operator, opSignature, actionData);
  }

  function testMockActionExecuteRevokedIntentShouldRevert(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    _setUpMainWallet(intentData, false);
    router.revoke(intentHash);

    IKSSessionIntentRouter.TokenData memory newTokenData =
      _getNewTokenData(intentData.tokenData, seed);
    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory swSignature, bytes memory opSignature) =
      _getCallerAndSignatures(mode, actionData);

    vm.startPrank(caller);
    vm.expectRevert(IKSSessionIntentRouter.IntentRevoked.selector);
    router.execute(intentHash, swSignature, operator, opSignature, actionData);
  }

  function testMockActionExecuteNonExistentIntentShouldRevert(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    IKSSessionIntentRouter.TokenData memory newTokenData =
      _getNewTokenData(intentData.tokenData, seed);
    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

    vm.warp(block.timestamp + 100);
    (address caller, bytes memory swSignature, bytes memory opSignature) =
      _getCallerAndSignatures(mode, actionData);

    vm.startPrank(caller);
    vm.expectRevert();
    router.execute(intentHash, swSignature, operator, opSignature, actionData);
  }

  function testMockActionDelegateExistedIntentShouldRevert(uint256 seed) public {
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);

    _setUpMainWallet(intentData, false);
    vm.prank(mainWallet);
    vm.expectRevert(IKSSessionIntentRouter.IntentAlreadyExists.selector);
    router.delegate(intentData);
  }

  function testMockActionExecuteTooLateShouldRevert(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    _setUpMainWallet(intentData, false);

    IKSSessionIntentRouter.TokenData memory newTokenData =
      _getNewTokenData(intentData.tokenData, seed);
    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

    vm.warp(intentData.coreData.endTime + 1);
    (address caller, bytes memory swSignature, bytes memory opSignature) =
      _getCallerAndSignatures(mode, actionData);

    vm.startPrank(caller);
    vm.expectRevert(IKSSessionIntentRouter.ExecuteTooLate.selector);
    router.execute(intentHash, swSignature, operator, opSignature, actionData);
  }

  function testMockActionExecuteTooEarlyShouldRevert(uint256 seed) public {
    uint256 mode = bound(seed, 0, 2);
    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(seed);
    bytes32 intentHash = router.hashTypedIntentData(intentData);

    _setUpMainWallet(intentData, false);

    IKSSessionIntentRouter.TokenData memory newTokenData =
      _getNewTokenData(intentData.tokenData, seed);
    IKSSessionIntentRouter.ActionData memory actionData = _getActionData(newTokenData, '');

    vm.warp(intentData.coreData.startTime - 1);
    (address caller, bytes memory swSignature, bytes memory opSignature) =
      _getCallerAndSignatures(mode, actionData);

    vm.startPrank(caller);
    vm.expectRevert(IKSSessionIntentRouter.ExecuteTooEarly.selector);
    router.execute(intentHash, swSignature, operator, opSignature, actionData);
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
    vm.startPrank(mainWallet);
    IKSSessionIntentRouter.IntentCoreData memory coreData = IKSSessionIntentRouter.IntentCoreData({
      mainWallet: mainWallet,
      sessionWallet: sessionWallet,
      startTime: block.timestamp + 10,
      endTime: block.timestamp + 1 days,
      actionContract: address(mockActionContract),
      actionSelector: MockActionContract.doNothing.selector,
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
      erc1155Mock.mint(mainWallet, i, tokenData.erc1155Data[0].amounts[i]);
    }
    erc1155Mock.setApprovalForAll(address(router), true);

    tokenData.erc20Data = new IKSSessionIntentRouter.ERC20Data[](1);
    tokenData.erc20Data[0] =
      IKSSessionIntentRouter.ERC20Data({token: address(erc20Mock), amount: bound(seed, 1, 1e18)});
    erc20Mock.mint(mainWallet, tokenData.erc20Data[0].amount);
    erc20Mock.approve(address(router), tokenData.erc20Data[0].amount);

    tokenData.erc721Data = new IKSSessionIntentRouter.ERC721Data[](1);
    tokenData.erc721Data[0] =
      IKSSessionIntentRouter.ERC721Data({token: address(erc721Mock), tokenId: seed});
    erc721Mock.mint(mainWallet, seed);
    erc721Mock.approve(address(router), seed);

    intentData = IKSSessionIntentRouter.IntentData({coreData: coreData, tokenData: tokenData});
    vm.stopPrank();
  }

  function _setUpMainWallet(
    IKSSessionIntentRouter.IntentData memory intentData,
    bool withSignedIntent
  ) internal {
    vm.startPrank(mainWallet);
    if (!withSignedIntent) {
      router.delegate(intentData);
    }
    vm.stopPrank();
  }

  function _getActionData(
    IKSSessionIntentRouter.TokenData memory tokenData,
    bytes memory actionCalldata
  ) internal view returns (IKSSessionIntentRouter.ActionData memory actionData) {
    actionData = IKSSessionIntentRouter.ActionData({
      tokenData: tokenData,
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
