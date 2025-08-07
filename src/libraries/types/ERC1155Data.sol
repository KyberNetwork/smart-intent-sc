// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../../interfaces/vendors/IKSBoringForwarder.sol';

import 'openzeppelin-contracts/contracts/interfaces/IERC1155.sol';

/**
 * @notice Data structure for ERC1155 token
 * @param token The address of the ERC1155 token
 * @param tokenIds The IDs of the ERC1155 token
 * @param amounts The amounts of the ERC1155 token
 */
struct ERC1155Data {
  address token;
  uint256[] tokenIds;
  uint256[] amounts;
}

using ERC1155DataLibrary for ERC1155Data global;

library ERC1155DataLibrary {
  /// @notice Thrown when collecting more than the intent allowance for ERC1155
  error ERC1155InsufficientIntentAllowance(
    bytes32 intentHash, address token, uint256 tokenId, uint256 allowance, uint256 needed
  );

  bytes32 constant ERC1155_DATA_TYPE_HASH =
    keccak256(abi.encodePacked('ERC1155Data(address token,uint256[] tokenIds,uint256[] amounts)'));

  function hash(ERC1155Data calldata self) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(
        ERC1155_DATA_TYPE_HASH,
        self.token,
        keccak256(abi.encodePacked(self.tokenIds)),
        keccak256(abi.encodePacked(self.amounts))
      )
    );
  }

  function approve(
    ERC1155Data calldata self,
    mapping(bytes32 => mapping(address => mapping(uint256 => uint256))) storage allowances,
    bytes32 intentHash
  ) internal {
    for (uint256 i = 0; i < self.tokenIds.length; i++) {
      allowances[intentHash][self.token][self.tokenIds[i]] = self.amounts[i];
    }
  }

  function collect(
    ERC1155Data calldata self,
    mapping(bytes32 => mapping(address => mapping(uint256 => uint256))) storage allowances,
    bytes32 intentHash,
    address mainAddress,
    address actionContract,
    IKSBoringForwarder forwarder
  ) internal {
    address token = self.token;
    for (uint256 i = 0; i < self.tokenIds.length; i++) {
      uint256 tokenId = self.tokenIds[i];
      uint256 amount = self.amounts[i];

      uint256 allowance = allowances[intentHash][token][tokenId];
      if (allowance < amount) {
        revert ERC1155InsufficientIntentAllowance(intentHash, token, tokenId, allowance, amount);
      }

      unchecked {
        allowances[intentHash][self.token][self.tokenIds[i]] = allowance - amount;
      }
    }

    if (address(forwarder) == address(0)) {
      IERC1155(token).safeBatchTransferFrom(
        mainAddress, address(this), self.tokenIds, self.amounts, ''
      );
      IERC1155(token).setApprovalForAll(actionContract, true);
    } else {
      IERC1155(token).safeBatchTransferFrom(
        mainAddress, address(forwarder), self.tokenIds, self.amounts, ''
      );
      bytes memory approveCalldata =
        abi.encodeCall(IERC1155.setApprovalForAll, (actionContract, true));
      forwarder.forwardPayable(token, approveCalldata);
    }
  }
}
