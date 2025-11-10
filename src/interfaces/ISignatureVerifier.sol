// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface ISignatureVerifier {
  /**
   * @notice Verify a signature
   * @param signer The signer address
   * @param hash The hash to verify
   * @param signature The signature to verify
   * @return valid True if the signature is valid, false otherwise
   */
  function verify(address signer, bytes32 hash, bytes calldata signature)
    external
    view
    returns (bool valid);
}
