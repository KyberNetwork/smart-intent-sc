// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ActionData} from './ActionData.sol';

struct ActionWitness {
  bytes32 intentHash;
  ActionData actionData;
}

using ActionWitnessLibrary for ActionWitness global;

library ActionWitnessLibrary {
  bytes32 constant ACTION_WITNESS_TYPE_HASH = keccak256(
    abi.encodePacked(
      'ActionWitness(bytes32 intentHash,ActionData actionData)ActionData(uint256[] erc20Ids,uint256[] erc20Amounts,uint256[] erc721Ids,FeeInfo feeInfo,uint256 approvalFlags,uint256 actionSelectorId,bytes actionCalldata,bytes hookActionData,bytes extraData,uint256 deadline,uint256 nonce)FeeInfo(address protocolRecipient,uint256[][] partnerFeeConfigs)'
    )
  );

  function hash(ActionWitness calldata self) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(
        ACTION_WITNESS_TYPE_HASH,
        self.intentHash,
        self.actionData.hash()
      )
    );
  }
}
