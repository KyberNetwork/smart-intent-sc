// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc/src/interfaces/IKSGenericForwarder.sol';

import 'ks-common-sc/src/libraries/token/PermitHelper.sol';

import 'openzeppelin-contracts/contracts/interfaces/IERC721.sol';

/**
 * @notice Data structure for ERC721 token
 * @param token The address of the ERC721 token
 * @param tokenId The ID of the ERC721 token
 * @param permitData The permit data for the ERC721 token
 */
struct ERC721Data {
  address token;
  uint256 tokenId;
  bytes permitData;
}

using ERC721DataLibrary for ERC721Data global;

library ERC721DataLibrary {
  using PermitHelper for address;

  /// @notice Thrown when collecting unapproved ERC721
  error ERC721InsufficientIntentApproval(bytes32 intentHash, address token, uint256 tokenId);

  bytes32 constant ERC721_DATA_TYPE_HASH =
    keccak256(abi.encodePacked('ERC721Data(address token,uint256 tokenId,bytes permitData)'));

  function hash(ERC721Data calldata self) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(ERC721_DATA_TYPE_HASH, self.token, self.tokenId, keccak256(self.permitData))
    );
  }

  function approve(
    ERC721Data calldata self,
    mapping(bytes32 => mapping(address => mapping(uint256 => bool))) storage approvals,
    bytes32 intentHash
  ) internal {
    approvals[intentHash][self.token][self.tokenId] = true;
    if (self.permitData.length > 0) {
      self.token.erc721Permit(self.tokenId, self.permitData);
    }
  }

  function collect(
    ERC721Data calldata self,
    mapping(bytes32 => mapping(address => mapping(uint256 => bool))) storage approvals,
    bytes32 intentHash,
    address mainAddress,
    address actionContract,
    IKSGenericForwarder forwarder,
    bool approvalFlag
  ) internal {
    address token = self.token;
    uint256 tokenId = self.tokenId;

    if (!approvals[intentHash][token][tokenId]) {
      revert ERC721InsufficientIntentApproval(intentHash, token, tokenId);
    }

    if (address(forwarder) == address(0)) {
      IERC721(token).safeTransferFrom(mainAddress, address(this), tokenId);
      if (approvalFlag) {
        IERC721(token).approve(actionContract, tokenId);
      }
    } else {
      IERC721(token).safeTransferFrom(mainAddress, address(forwarder), tokenId);
      if (approvalFlag) {
        bytes memory approveCalldata = abi.encodeCall(IERC721.approve, (actionContract, tokenId));
        forwarder.forward(token, approveCalldata);
      }
    }
  }
}
