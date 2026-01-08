// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

/**
 * @notice Data structure for core components of intent
 * @param mainAddress The main address
 * @param signatureVerifier The address of the signature verifier
 * @param delegatedKey The delegated key
 * @param actionContracts The addresses of the action contracts
 * @param actionSelectors The selectors of the action functions
 * @param hook The address of the hook
 * @param hookIntentData The intent data for the hook
 */
struct IntentCoreData {
  address mainAddress;
  address signatureVerifier;
  bytes delegatedKey;
  address[] actionContracts;
  bytes4[] actionSelectors;
  address hook;
  bytes hookIntentData;
}

using IntentCoreDataLibrary for IntentCoreData global;

library IntentCoreDataLibrary {
  bytes32 constant INTENT_CORE_DATA_TYPE_HASH = keccak256(
    abi.encodePacked(
      'IntentCoreData(address mainAddress,address signatureVerifier,bytes delegatedKey,address[] actionContracts,bytes4[] actionSelectors,address hook,bytes hookIntentData)'
    )
  );

  function hash(IntentCoreData calldata self) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(
        INTENT_CORE_DATA_TYPE_HASH,
        self.mainAddress,
        self.signatureVerifier,
        keccak256(self.delegatedKey),
        keccak256(abi.encodePacked(self.actionContracts)),
        keccak256(abi.encodePacked(self.actionSelectors)),
        self.hook,
        keccak256(self.hookIntentData)
      )
    );
  }
}
