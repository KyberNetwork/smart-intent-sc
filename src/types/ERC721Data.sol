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

  bytes32 constant ERC721_DATA_TYPE_HASH =
    keccak256(abi.encodePacked('ERC721Data(address token,uint256 tokenId,bytes permitData)'));

  function hash(ERC721Data calldata self) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(ERC721_DATA_TYPE_HASH, self.token, self.tokenId, keccak256(self.permitData))
    );
  }

  function collect(
    address token,
    uint256 tokenId,
    address mainAddress,
    address actionContract,
    IKSGenericForwarder forwarder,
    bool approvalFlag
  ) internal {
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
