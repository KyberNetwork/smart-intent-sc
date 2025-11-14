// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ERC20Data} from './ERC20Data.sol';
import {ERC721Data} from './ERC721Data.sol';

struct TokenData {
  ERC20Data[] erc20Data;
  ERC721Data[] erc721Data;
}

using TokenDataLibrary for TokenData global;

library TokenDataLibrary {
  bytes32 constant TOKEN_DATA_TYPE_HASH = keccak256(
    abi.encodePacked(
      'TokenData(ERC20Data[] erc20Data,ERC721Data[] erc721Data)ERC20Data(address token,uint256 amount,bytes permitData)ERC721Data(address token,uint256 tokenId,bytes permitData)'
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

    return keccak256(
      abi.encode(
        TOKEN_DATA_TYPE_HASH,
        keccak256(abi.encodePacked(erc20DataHashes)),
        keccak256(abi.encodePacked(erc721DataHashes))
      )
    );
  }
}
