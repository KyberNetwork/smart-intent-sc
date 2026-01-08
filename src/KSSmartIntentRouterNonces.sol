// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IKSSmartIntentRouter} from './interfaces/IKSSmartIntentRouter.sol';

abstract contract KSSmartIntentRouterNonces is IKSSmartIntentRouter {
  /// @inheritdoc IKSSmartIntentRouter
  mapping(bytes32 intentHash => mapping(uint256 word => uint256 bitmap)) public nonces;

  function _useUnorderedNonce(bytes32 intentHash, uint256 nonce) internal {
    uint256 wordPos = nonce >> 8;
    uint256 bitPos = uint8(nonce);

    uint256 bit = 1 << bitPos;
    uint256 flipped = nonces[intentHash][wordPos] ^= bit;
    if (flipped & bit == 0) {
      revert NonceAlreadyUsed(intentHash, nonce);
    }

    emit UseNonce(intentHash, nonce);
  }
}
