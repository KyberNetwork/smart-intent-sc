// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './IntentCoreData.sol';
import './TokenData.sol';

import 'openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol';

/**
 * @notice Data structure for action
 * @param tokenData The token data for the action
 * @param approvalFlags The approval flags for the tokens
 * @param actionSelectorId The ID of the action selector
 * @param actionCalldata The calldata for the action
 * @param hookActionData The action data for the hook
 * @param extraData The extra data for the action
 * @param deadline The deadline for the action
 * @param nonce The nonce for the action
 */
struct ActionData {
  TokenData tokenData;
  uint256 approvalFlags;
  uint256 actionSelectorId;
  bytes actionCalldata;
  bytes hookActionData;
  bytes extraData;
  uint256 deadline;
  uint256 nonce;
}

using ActionDataLibrary for ActionData global;

library ActionDataLibrary {
  bytes32 constant ACTION_DATA_TYPE_HASH = keccak256(
    abi.encodePacked(
      'ActionData(TokenData tokenData,uint256 approvalFlags,uint256 actionSelectorId,bytes actionCalldata,bytes hookActionData,bytes extraData,uint256 deadline,uint256 nonce)ERC20Data(address token,uint256 amount,bytes permitData)ERC721Data(address token,uint256 tokenId,bytes permitData)TokenData(ERC20Data[] erc20Data,ERC721Data[] erc721Data)'
    )
  );

  function hash(ActionData calldata self) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(
        ACTION_DATA_TYPE_HASH,
        self.tokenData.hash(),
        self.approvalFlags,
        self.actionSelectorId,
        keccak256(self.actionCalldata),
        keccak256(self.hookActionData),
        keccak256(self.extraData),
        self.deadline,
        self.nonce
      )
    );
  }
}
