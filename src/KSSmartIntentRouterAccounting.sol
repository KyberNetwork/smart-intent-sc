// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './KSSmartIntentStorage.sol';

import 'ks-common-sc/src/base/ManagementRescuable.sol';

import 'ks-common-sc/src/interfaces/IKSGenericForwarder.sol';
import 'ks-common-sc/src/libraries/token/PermitHelper.sol';
import 'ks-common-sc/src/libraries/token/TokenHelper.sol';

import 'openzeppelin-contracts/contracts/interfaces/IERC721Receiver.sol';

abstract contract KSSmartIntentRouterAccounting is KSSmartIntentStorage, ManagementRescuable {
  using TokenHelper for address;
  using PermitHelper for address;

  mapping(bytes32 => mapping(address => uint256)) public erc20Allowances;

  /// @notice Set the tokens' allowances for the intent
  function _approveTokens(bytes32 intentHash, TokenData calldata tokenData, address mainAddress)
    internal
  {
    for (uint256 i = 0; i < tokenData.erc20Data.length; i++) {
      ERC20Data calldata erc20Data = tokenData.erc20Data[i];

      erc20Allowances[intentHash][erc20Data.token] = erc20Data.amount;

      if (erc20Data.permitData.length > 0) {
        erc20Data.token.erc20Permit(mainAddress, erc20Data.permitData);
      }
    }
    for (uint256 i = 0; i < tokenData.erc721Data.length; i++) {
      ERC721Data calldata erc721Data = tokenData.erc721Data[i];

      if (erc721Data.permitData.length > 0) {
        erc721Data.token.erc721Permit(erc721Data.tokenId, erc721Data.permitData);
      }
    }
  }

  /// @notice Transfer the tokens to this contract and update the allowances
  function _collectTokens(
    bytes32 intentHash,
    address mainAddress,
    address actionContract,
    TokenData calldata tokenData,
    ActionData calldata actionData,
    IKSGenericForwarder _forwarder,
    uint256[] memory fees
  ) internal checkLengths(actionData.erc20Ids.length, actionData.erc20Amounts.length) {
    uint256 approvalFlags = actionData.approvalFlags;

    for (uint256 i = 0; i < actionData.erc20Ids.length; i++) {
      address token = tokenData.erc20Data[actionData.erc20Ids[i]].token;

      _spentAllowance(intentHash, token, actionData.erc20Amounts[i]);

      ERC20DataLibrary.collect(
        token,
        actionData.erc20Amounts[i],
        mainAddress,
        actionContract,
        fees[i],
        _checkFlag(approvalFlags, i),
        _forwarder,
        actionData.partnerFeeInfos[i],
        actionData.protocolRecipient
      );
    }
    approvalFlags >>= tokenData.erc20Data.length;

    for (uint256 i = 0; i < actionData.erc721Ids.length; i++) {
      address token = tokenData.erc721Data[actionData.erc721Ids[i]].token;
      uint256 tokenId = tokenData.erc721Data[actionData.erc721Ids[i]].tokenId;

      ERC721DataLibrary.collect(
        token, tokenId, mainAddress, actionContract, _forwarder, _checkFlag(approvalFlags, i)
      );
    }
  }

  function _spentAllowance(bytes32 intentHash, address token, uint256 amount) internal {
    uint256 allowance = erc20Allowances[intentHash][token];
    if (allowance < amount) {
      revert ERC20InsufficientIntentAllowance(intentHash, token, allowance, amount);
    }

    unchecked {
      erc20Allowances[intentHash][token] = allowance - amount;
    }
  }

  function onERC721Received(address, address, uint256, bytes calldata)
    external
    pure
    returns (bytes4)
  {
    return IERC721Receiver.onERC721Received.selector;
  }

  function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
    return interfaceId == type(IERC721Receiver).interfaceId || super.supportsInterface(interfaceId);
  }

  function _checkFlag(uint256 flag, uint256 index) internal pure returns (bool result) {
    assembly ("memory-safe") {
      result := and(shr(index, flag), 1)
    }
  }
}
