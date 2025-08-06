// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './IntentCoreData.sol';
import './TokenData.sol';

import '../../interfaces/actions/IKSGenericExecutor.sol';
import '../../interfaces/actions/IKSSwapRouterV2.sol';
import '../../interfaces/actions/IKSSwapRouterV3.sol';
import '../../interfaces/actions/IKSZapRouter.sol';

import 'openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol';

/**
 * @notice Data structure for action
 * @param tokenData The token data for the action
 * @param actionSelectorId The ID of the action selector
 * @param actionCalldata The calldata for the action
 * @param hookActionData The action data for the hook
 * @param extraData The extra data for the action
 * @param deadline The deadline for the action
 * @param nonce The nonce for the action
 */
struct ActionData {
  TokenData tokenData;
  uint256 actionSelectorId;
  bytes actionCalldata;
  bytes hookActionData;
  bytes extraData;
  uint256 deadline;
  uint256 nonce;
}

using ActionDataLibrary for ActionData global;

library ActionDataLibrary {
  /// @notice Thrown when the signature is not from the session wallet
  error InvalidDelegatedAddressSignature();

  /// @notice Thrown when the signature is not from the guardian
  error InvalidGuardianSignature();

  /// @notice Thrown when the action selector is not valid
  error InvalidActionSelector(bytes4 actionSelector);

  bytes32 constant ACTION_DATA_TYPE_HASH = keccak256(
    abi.encodePacked(
      'ActionData(TokenData tokenData,uint256 actionSelectorId,bytes actionCalldata,bytes hookActionData,bytes extraData,uint256 deadline,uint256 nonce)ERC1155Data(address token,uint256[] tokenIds,uint256[] amounts)ERC20Data(address token,uint256 amount,bytes permitData)ERC721Data(address token,uint256 tokenId,bytes permitData)TokenData(ERC20Data[] erc20Data,ERC721Data[] erc721Data,ERC1155Data[] erc1155Data)'
    )
  );

  function validate(
    ActionData calldata self,
    bytes32 actionHash,
    IntentCoreData calldata intent,
    bytes memory daSignature,
    address guardian,
    bytes memory gdSignature
  ) internal view {
    if (msg.sender != intent.delegatedAddress) {
      if (!SignatureChecker.isValidSignatureNow(intent.delegatedAddress, actionHash, daSignature)) {
        revert InvalidDelegatedAddressSignature();
      }
    }
    if (msg.sender != guardian) {
      if (!SignatureChecker.isValidSignatureNow(guardian, actionHash, gdSignature)) {
        revert InvalidGuardianSignature();
      }
    }

    bytes4 actionSelector = intent.actionSelectors[self.actionSelectorId];
    if (
      actionSelector != IKSGenericExecutor.execute.selector
        && actionSelector != IKSSwapRouterV2.swap.selector
        && actionSelector != IKSSwapRouterV2.swapSimpleMode.selector
        && actionSelector != IKSSwapRouterV3.swap.selector
        && actionSelector != IKSZapRouter.zap.selector
    ) {
      revert InvalidActionSelector(actionSelector);
    }
  }

  function hash(ActionData calldata self) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(
        ACTION_DATA_TYPE_HASH,
        self.tokenData.hash(),
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
