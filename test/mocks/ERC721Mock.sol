// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ERC721} from 'openzeppelin-contracts/token/ERC721/ERC721.sol';

contract ERC721Mock is ERC721 {
  constructor() ERC721('ERC721Mock', 'ERC721M') {}

  function mint(address to, uint256 tokenId) external {
    _mint(to, tokenId);
  }
}
