// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IntentCoreData} from './IntentCoreData.sol';
import {TokenData} from './TokenData.sol';

/**
 * @notice Data structure for intent data
 * @param coreData The core data for the intent
 * @param tokenData The token data for the intent
 * @param extraData The extra data for the intent
 */
struct IntentData {
  IntentCoreData coreData;
  TokenData tokenData;
  bytes extraData;
}

using IntentDataLibrary for IntentData global;

library IntentDataLibrary {
  bytes32 constant INTENT_DATA_TYPE_HASH = keccak256(
    abi.encodePacked(
      'IntentData(IntentCoreData coreData,TokenData tokenData,bytes extraData)ERC20Data(address token,uint256 amount,bytes permitData)ERC721Data(address token,uint256 tokenId,bytes permitData)IntentCoreData(address mainAddress,address signatureVerifier,bytes delegatedKey,address[] actionContracts,bytes4[] actionSelectors,address hook,bytes hookIntentData)TokenData(ERC20Data[] erc20Data,ERC721Data[] erc721Data)'
    )
  );

  function hash(IntentData calldata self) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(
        INTENT_DATA_TYPE_HASH,
        self.coreData.hash(),
        self.tokenData.hash(),
        keccak256(self.extraData)
      )
    );
  }
}
