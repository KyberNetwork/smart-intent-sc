// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc/script/Base.s.sol';
import 'src/SignatureVerifier.sol';

contract DeploySignatureVerifier is BaseScript {
  function run() external {
    vm.startBroadcast();
    SignatureVerifier signatureVerifier = new SignatureVerifier();

    _writeAddress('signature-verifier', address(signatureVerifier));

    vm.stopBroadcast();
  }
}
