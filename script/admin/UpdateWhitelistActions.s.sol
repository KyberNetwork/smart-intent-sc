// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc-script/script/Base.s.sol';

import {KSSmartIntentRouter} from 'src/KSSmartIntentRouter.sol';

/// @dev One entry of `action-contracts.json`. Fields are alphabetical, as `vm.parseJson` requires.
struct ActionContract {
  address addr;
  string name;
}

contract UpdateWhitelistActions is BaseScript {
  bytes32 constant ACTION_CONTRACT_ROLE = keccak256('ACTION_CONTRACT_ROLE');

  /**
   * @notice Grants ACTION_CONTRACT_ROLE to every action contract in `action-contracts.json` that
   *         the router does not whitelist yet, on each chain in `chainIds`
   * @dev Usage:
   *   forge script script/admin/UpdateWhitelistActions.s.sol --sig "run(string[])" "[56,8453]" \
   *     --account <admin> --broadcast
   */
  function run(string[] memory chainIds) external multiChain(chainIds) {
    KSSmartIntentRouter router = KSSmartIntentRouter(payable(_readAddress('router')));
    ActionContract[] memory entries = abi.decode(
      vm.parseJson(_getJsonString('action-contracts'), _toDotChainId(block.chainid)),
      (ActionContract[])
    );

    address[] memory toWhitelist = new address[](entries.length);
    uint256 count;
    for (uint256 i = 0; i < entries.length; i++) {
      if (!router.hasRole(ACTION_CONTRACT_ROLE, entries[i].addr)) {
        toWhitelist[count++] = entries[i].addr;
        console.log(
          'Whitelisting %s (%s) on chain %s', entries[i].name, entries[i].addr, block.chainid
        );
      }
    }

    if (count == 0) {
      console.log('Nothing to whitelist on chain %s', block.chainid);
      return;
    }

    assembly ('memory-safe') {
      mstore(toWhitelist, count)
    }
    router.batchGrantRole(ACTION_CONTRACT_ROLE, toWhitelist);
  }
}
