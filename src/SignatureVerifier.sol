// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ISignatureVerifier} from './interfaces/ISignatureVerifier.sol';

import {P256} from 'openzeppelin-contracts/contracts/utils/cryptography/P256.sol';
import {
  SignatureChecker
} from 'openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol';

import {CalldataDecoder} from 'ks-common-sc/src/libraries/calldata/CalldataDecoder.sol';

import 'forge-std/console.sol';

contract SignatureVerifier is ISignatureVerifier {
  using CalldataDecoder for bytes;

  function verify(address signer, bytes32 hash, bytes calldata signature)
    public
    view
    returns (bool)
  {
    if (signature.length == 128) {
      bytes32 r = signature.decodeBytes32(0);
      bytes32 s = signature.decodeBytes32(1);
      bytes32 qx = signature.decodeBytes32(2);
      bytes32 qy = signature.decodeBytes32(3);

      uint256 pubKeyHash;
      assembly ('memory-safe') {
        mstore(0x00, qx)
        mstore(0x20, qy)
        pubKeyHash := keccak256(0x00, 0x40)
      }

      if (uint160(signer) != uint160(pubKeyHash)) {
        return false;
      }

      if (!P256.verify(hash, r, s, qx, qy)) {
        return false;
      }
    } else {
      if (!SignatureChecker.isValidSignatureNow(signer, hash, signature)) {
        return false;
      }
    }

    return true;
  }
}
