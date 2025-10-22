// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './FeeInfo.sol';
import './IntentCoreData.sol';
import './TokenData.sol';

import 'openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol';

/**
 * @notice Data structure for action
 * @param erc20Ids The IDs of the ERC20 tokens in the intent data
 * @param erc20Amounts The amounts of the ERC20 tokens
 * @param erc721Ids The IDs of the ERC721 tokens in the intent data
 * @param feeInfo The fee info for the action
 * @param approvalFlags The approval flags for the tokens
 * @param actionSelectorId The ID of the action selector
 * @param actionCalldata The calldata for the action
 * @param hookActionData The action data for the hook
 * @param extraData The extra data for the action
 * @param deadline The deadline for the action
 * @param nonce The nonce for the action
 */
struct ActionData {
  uint256[] erc20Ids;
  uint256[] erc20Amounts;
  uint256[] erc721Ids;
  FeeInfo feeInfo;
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
      'ActionData(uint256[] erc20Ids,uint256[] erc20Amounts,uint256[] erc721Ids,FeeInfo feeInfo,uint256 approvalFlags,uint256 actionSelectorId,bytes actionCalldata,bytes hookActionData,bytes extraData,uint256 deadline,uint256 nonce)FeeInfo(address protocolRecipient,PartnersFeeInfo[] partnersFeeInfos)PartnersFeeInfo(bool feeMode,uint256[] feeConfigs)'
    )
  );

  function hash(ActionData calldata self) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(
        ACTION_DATA_TYPE_HASH,
        keccak256(abi.encodePacked(self.erc20Ids)),
        keccak256(abi.encodePacked(self.erc20Amounts)),
        keccak256(abi.encodePacked(self.erc721Ids)),
        self.feeInfo.hash(),
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
