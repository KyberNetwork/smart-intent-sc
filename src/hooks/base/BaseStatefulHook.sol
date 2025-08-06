// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './BaseHook.sol';

abstract contract BaseStatefulHook is BaseHook {
  error NonWhitelistedRouter(address router);

  mapping(address => bool) public whitelistedRouters;

  constructor(address[] memory initialRouters) {
    for (uint256 i = 0; i < initialRouters.length; i++) {
      whitelistedRouters[initialRouters[i]] = true;
    }
  }

  modifier onlyWhitelistedRouter() {
    if (!whitelistedRouters[msg.sender]) {
      revert NonWhitelistedRouter(msg.sender);
    }
    _;
  }
}
