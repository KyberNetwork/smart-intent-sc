// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './interfaces/IKSSmartIntentRouter.sol';
import './interfaces/vendors/IKSBoringForwarder.sol';

import 'ks-common-sc/src/base/ManagementRescuable.sol';
import 'ks-common-sc/src/libraries/token/PermitHelper.sol';
import 'ks-common-sc/src/libraries/token/TokenHelper.sol';

import 'openzeppelin-contracts/contracts/interfaces/IERC1155.sol';
import 'openzeppelin-contracts/contracts/interfaces/IERC1155Receiver.sol';
import 'openzeppelin-contracts/contracts/interfaces/IERC721Receiver.sol';

abstract contract KSSmartIntentRouterAccounting is IKSSmartIntentRouter, ManagementRescuable {
  using TokenHelper for address;
  using PermitHelper for address;

  mapping(bytes32 => mapping(address => mapping(uint256 => uint256))) public erc1155Allowances;

  mapping(bytes32 => mapping(address => uint256)) public erc20Allowances;

  mapping(bytes32 => mapping(address => mapping(uint256 => bool))) public erc721Approvals;

  /// @notice Set the tokens' allowances for the intent
  function _approveTokens(bytes32 intentHash, TokenData calldata tokenData, address mainAddress)
    internal
  {
    for (uint256 i = 0; i < tokenData.erc20Data.length; i++) {
      tokenData.erc20Data[i].approve(erc20Allowances, intentHash, mainAddress);
    }
    for (uint256 i = 0; i < tokenData.erc721Data.length; i++) {
      tokenData.erc721Data[i].approve(erc721Approvals, intentHash);
    }
    for (uint256 i = 0; i < tokenData.erc1155Data.length; i++) {
      tokenData.erc1155Data[i].approve(erc1155Allowances, intentHash);
    }
  }

  /// @notice Transfer the tokens to this contract and update the allowances
  function _collectTokens(
    bytes32 intentHash,
    address mainAddress,
    address actionContract,
    TokenData calldata tokenData,
    IKSBoringForwarder forwarder,
    uint256[] memory fees
  ) internal {
    for (uint256 i = 0; i < tokenData.erc20Data.length; i++) {
      tokenData.erc20Data[i].collect(
        erc20Allowances, intentHash, mainAddress, actionContract, forwarder, fees[i]
      );
    }
    for (uint256 i = 0; i < tokenData.erc721Data.length; i++) {
      tokenData.erc721Data[i].collect(
        erc721Approvals, intentHash, mainAddress, actionContract, forwarder
      );
    }
    for (uint256 i = 0; i < tokenData.erc1155Data.length; i++) {
      tokenData.erc1155Data[i].collect(
        erc1155Allowances, intentHash, mainAddress, actionContract, forwarder
      );
    }

    emit CollectTokens(intentHash, tokenData);
  }

  function onERC721Received(address, address, uint256, bytes calldata)
    external
    pure
    returns (bytes4)
  {
    return IERC721Receiver.onERC721Received.selector;
  }

  function onERC1155Received(address, address, uint256, uint256, bytes calldata)
    external
    pure
    returns (bytes4)
  {
    return IERC1155Receiver.onERC1155Received.selector;
  }

  function onERC1155BatchReceived(
    address,
    address,
    uint256[] calldata,
    uint256[] calldata,
    bytes calldata
  ) external pure returns (bytes4) {
    return IERC1155Receiver.onERC1155BatchReceived.selector;
  }

  function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
    return interfaceId == type(IERC1155Receiver).interfaceId
      || interfaceId == type(IERC721Receiver).interfaceId || super.supportsInterface(interfaceId);
  }

  function _safeApproveInf(address token, address spender) internal {
    token.forceApprove(spender, type(uint256).max);
  }
}
