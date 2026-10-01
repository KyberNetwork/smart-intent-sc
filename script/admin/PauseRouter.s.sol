// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc-script/script/Base.s.sol';

import {KSSmartIntentRouter} from 'src/KSSmartIntentRouter.sol';

contract PauseRouter is BaseScript {
  /**
   * @notice Pauses the router on each chain in `chainIds`. Callable by a guardian or the admin.
   * @dev Usage:
   *   forge script script/admin/PauseRouter.s.sol --sig "run(string[])" "[56,8453]" \
   *     --account <guardian> --broadcast
   */
  function run(string[] memory chainIds) external multiChain(chainIds) {
    KSSmartIntentRouter router = KSSmartIntentRouter(payable(_readAddress('router')));

    if (router.paused()) {
      console.log('Router already paused on chain %s', block.chainid);
      return;
    }

    router.pause();
    console.log('Paused router %s on chain %s', address(router), block.chainid);
  }

  /**
   * @notice Unpauses the router on each chain in `chainIds`. Callable by the admin only.
   * @dev Usage:
   *   forge script script/admin/PauseRouter.s.sol --sig "unpause(string[])" "[56,8453]" \
   *     --account <admin> --broadcast
   */
  function unpause(string[] memory chainIds) external multiChain(chainIds) {
    KSSmartIntentRouter router = KSSmartIntentRouter(payable(_readAddress('router')));

    if (!router.paused()) {
      console.log('Router not paused on chain %s', block.chainid);
      return;
    }

    router.unpause();
    console.log('Unpaused router %s on chain %s', address(router), block.chainid);
  }
}
