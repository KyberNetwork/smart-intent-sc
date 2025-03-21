// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'src/KSSessionIntentRouter.sol';

contract KSSessionIntentRouterHarness is KSSessionIntentRouter {
  constructor(
    address _owner,
    address[] memory _initialOperators,
    address[] memory _initialGuardians
  ) KSSessionIntentRouter(_owner, _initialOperators, _initialGuardians) {}

  function hashTypedIntentData(IntentData calldata intentData) public view returns (bytes32) {
    return _hashTypedIntentData(intentData);
  }

  function hashTypedActionData(ActionData calldata actionData) public view returns (bytes32) {
    return _hashTypedActionData(actionData);
  }

  function getERC1155Allowance(bytes32 intentHash, address token, uint256 tokenId)
    public
    view
    returns (uint256)
  {
    return erc1155Allowances[intentHash][token][tokenId];
  }

  function getERC20Allowance(bytes32 intentHash, address token) public view returns (uint256) {
    return erc20Allowances[intentHash][token];
  }

  function getERC721Approval(bytes32 intentHash, address token, uint256 tokenId)
    public
    view
    returns (bool)
  {
    return erc721Approvals[intentHash][token][tokenId];
  }
}
