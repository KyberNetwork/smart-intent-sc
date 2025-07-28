// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './interfaces/IKSSessionIntentValidator.sol';
import './libraries/TokenLibrary.sol';

import 'ks-growth-utils-sc/KSRescueV2.sol';

import 'openzeppelin-contracts/interfaces/IERC1155Receiver.sol';
import 'openzeppelin-contracts/interfaces/IERC721Receiver.sol';

abstract contract KSSessionIntentRouterAccounting is IKSSessionIntentRouter, KSRescueV2 {
  using TokenLibrary for address;

  mapping(bytes32 => mapping(address => mapping(uint256 => uint256))) public erc1155Allowances;

  mapping(bytes32 => mapping(address => uint256)) public erc20Allowances;

  mapping(bytes32 => mapping(address => mapping(uint256 => bool))) public erc721Approvals;

  constructor(address initialOwner, address[] memory initialGuardians) Ownable(initialOwner) {
    for (uint256 i = 0; i < initialGuardians.length; i++) {
      guardians[initialGuardians[i]] = true;

      emit UpdateGuardian(initialGuardians[i], true);
    }
  }

  /// @notice Set the tokens' allowances for the intent
  function _approveTokens(bytes32 intentHash, TokenData calldata tokenData) internal {
    for (uint256 i = 0; i < tokenData.erc1155Data.length; i++) {
      ERC1155Data calldata erc1155Data = tokenData.erc1155Data[i];
      for (uint256 j = 0; j < erc1155Data.tokenIds.length; j++) {
        erc1155Allowances[intentHash][erc1155Data.token][erc1155Data.tokenIds[j]] =
          erc1155Data.amounts[j];
      }
    }
    for (uint256 i = 0; i < tokenData.erc20Data.length; i++) {
      ERC20Data calldata erc20Data = tokenData.erc20Data[i];
      erc20Allowances[intentHash][erc20Data.token] = erc20Data.amount;
    }
    for (uint256 i = 0; i < tokenData.erc721Data.length; i++) {
      ERC721Data calldata erc721Data = tokenData.erc721Data[i];
      erc721Approvals[intentHash][erc721Data.token][erc721Data.tokenId] = true;
    }
  }

  /// @notice Transfer the tokens to this contract and update the allowances
  function _collectTokens(
    bytes32 intentHash,
    address mainAddress,
    address actionContract,
    TokenData calldata tokenData
  ) internal {
    for (uint256 i = 0; i < tokenData.erc1155Data.length; i++) {
      ERC1155Data calldata erc1155Data = tokenData.erc1155Data[i];
      IERC1155 token = IERC1155(erc1155Data.token);
      for (uint256 j = 0; j < erc1155Data.tokenIds.length; j++) {
        uint256 allowance =
          erc1155Allowances[intentHash][erc1155Data.token][erc1155Data.tokenIds[j]];
        require(
          allowance >= erc1155Data.amounts[j],
          ERC1155InsufficientIntentAllowance(
            intentHash,
            erc1155Data.token,
            erc1155Data.tokenIds[j],
            allowance,
            erc1155Data.amounts[j]
          )
        );
        unchecked {
          erc1155Allowances[intentHash][erc1155Data.token][erc1155Data.tokenIds[j]] =
            allowance - erc1155Data.amounts[j];
        }
      }
      token.safeBatchTransferFrom(
        mainAddress, address(this), erc1155Data.tokenIds, erc1155Data.amounts, ''
      );
      token.setApprovalForAll(actionContract, true);
    }
    for (uint256 i = 0; i < tokenData.erc20Data.length; i++) {
      ERC20Data calldata erc20Data = tokenData.erc20Data[i];
      uint256 allowance = erc20Allowances[intentHash][erc20Data.token];
      require(
        allowance >= erc20Data.amount,
        ERC20InsufficientIntentAllowance(intentHash, erc20Data.token, allowance, erc20Data.amount)
      );
      unchecked {
        erc20Allowances[intentHash][erc20Data.token] = allowance - erc20Data.amount;
      }
      erc20Data.token.safeTransferFrom(mainAddress, address(this), erc20Data.amount);
      _safeApproveInf(erc20Data.token, actionContract);
    }
    for (uint256 i = 0; i < tokenData.erc721Data.length; i++) {
      ERC721Data calldata erc721Data = tokenData.erc721Data[i];
      IERC721 token = IERC721(erc721Data.token);
      require(
        erc721Approvals[intentHash][erc721Data.token][erc721Data.tokenId],
        ERC721InsufficientIntentApproval(intentHash, address(token), erc721Data.tokenId)
      );
      token.safeTransferFrom(mainAddress, address(this), erc721Data.tokenId);
      token.approve(actionContract, erc721Data.tokenId);
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

  function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
    return interfaceId == type(IERC1155Receiver).interfaceId
      || interfaceId == type(IERC721Receiver).interfaceId;
  }

  function _safeApproveInf(address token, address spender) internal {
    token.forceApprove(spender, type(uint256).max);
  }
}
