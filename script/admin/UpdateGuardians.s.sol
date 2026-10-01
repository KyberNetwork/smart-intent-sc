// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc-script/script/Base.s.sol';

import {KSRoles} from 'ks-common-sc/src/libraries/KSRoles.sol';
import {KSSmartIntentRouter} from 'src/KSSmartIntentRouter.sol';

contract UpdateGuardians is BaseScript {
  /**
   * @notice Grants GUARDIAN_ROLE to every guardian in `router-guardians.json` that does not hold it
   *         yet, on each chain in `chainIds`
   * @dev Usage:
   *   forge script script/admin/UpdateGuardians.s.sol --sig "run(string[])" "[56,8453]" \
   *     --account <admin> --broadcast
   */
  function run(string[] memory chainIds) external multiChain(chainIds) {
    KSSmartIntentRouter router = KSSmartIntentRouter(payable(_readAddress('router')));
    address[] memory guardians = _readAddressArray('router-guardians');

    address[] memory toGrant = new address[](guardians.length);
    uint256 count;
    for (uint256 i = 0; i < guardians.length; i++) {
      if (!router.hasRole(KSRoles.GUARDIAN_ROLE, guardians[i])) {
        toGrant[count++] = guardians[i];
        console.log('Granting guardian %s on chain %s', guardians[i], block.chainid);
      }
    }

    if (count == 0) {
      console.log('No guardian to grant on chain %s', block.chainid);
      return;
    }

    assembly ('memory-safe') {
      mstore(toGrant, count)
    }
    router.batchGrantRole(KSRoles.GUARDIAN_ROLE, toGrant);
  }

  /**
   * @notice Revokes GUARDIAN_ROLE from each of `guardians` that still holds it, on each chain in
   *         `chainIds`
   * @dev Usage:
   *   forge script script/admin/UpdateGuardians.s.sol --sig "revoke(string[],address[])" \
   *     "[56,8453]" "[0x...]" --account <admin> --broadcast
   */
  function revoke(string[] memory chainIds, address[] memory guardians)
    external
    multiChain(chainIds)
  {
    KSSmartIntentRouter router = KSSmartIntentRouter(payable(_readAddress('router')));

    address[] memory toRevoke = new address[](guardians.length);
    uint256 count;
    for (uint256 i = 0; i < guardians.length; i++) {
      if (router.hasRole(KSRoles.GUARDIAN_ROLE, guardians[i])) {
        toRevoke[count++] = guardians[i];
        console.log('Revoking guardian %s on chain %s', guardians[i], block.chainid);
      }
    }

    if (count == 0) {
      console.log('No guardian to revoke on chain %s', block.chainid);
      return;
    }

    assembly ('memory-safe') {
      mstore(toRevoke, count)
    }
    router.batchRevokeRole(KSRoles.GUARDIAN_ROLE, toRevoke);
  }
}
