// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './ERC1155Data.sol';
import './ERC20Data.sol';
import './ERC721Data.sol';

struct TokenData {
  ERC20Data[] erc20Data;
  ERC721Data[] erc721Data;
  ERC1155Data[] erc1155Data;
}

using TokenDataLibrary for TokenData global;

library TokenDataLibrary {
  bytes32 constant TOKEN_DATA_TYPE_HASH = keccak256(
    abi.encodePacked(
      'TokenData(ERC20Data[] erc20Data,ERC721Data[] erc721Data,ERC1155Data[] erc1155Data)ERC1155Data(address token,uint256[] tokenIds,uint256[] amounts)ERC20Data(address token,uint256 amount,bytes permitData)ERC721Data(address token,uint256 tokenId,bytes permitData)'
    )
  );

  function hash(TokenData calldata self) internal pure returns (bytes32) {
    bytes32[] memory erc20DataHashes = new bytes32[](self.erc20Data.length);
    for (uint256 i = 0; i < self.erc20Data.length; i++) {
      erc20DataHashes[i] = self.erc20Data[i].hash();
    }

    bytes32[] memory erc721DataHashes = new bytes32[](self.erc721Data.length);
    for (uint256 i = 0; i < self.erc721Data.length; i++) {
      erc721DataHashes[i] = self.erc721Data[i].hash();
    }

    bytes32[] memory erc1155DataHashes = new bytes32[](self.erc1155Data.length);
    for (uint256 i = 0; i < self.erc1155Data.length; i++) {
      erc1155DataHashes[i] = self.erc1155Data[i].hash();
    }

    return keccak256(
      abi.encode(
        TOKEN_DATA_TYPE_HASH,
        keccak256(abi.encodePacked(erc20DataHashes)),
        keccak256(abi.encodePacked(erc721DataHashes)),
        keccak256(abi.encodePacked(erc1155DataHashes))
      )
    );
  }
}
