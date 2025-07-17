// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ERC1155} from '@openzeppelin-contracts/token/ERC1155/ERC1155.sol';

contract ERC1155Mock is ERC1155 {
  constructor() ERC1155('ERC1155Mock') {}

  function mint(address to, uint256 id, uint256 amount) external {
    _mint(to, id, amount, '');
  }
}
