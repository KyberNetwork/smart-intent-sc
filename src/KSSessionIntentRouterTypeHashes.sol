// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './interfaces/IKSSessionIntentValidator.sol';

import 'openzeppelin-contracts/utils/cryptography/EIP712.sol';

abstract contract KSSessionIntentRouterTypeHashes is
  IKSSessionIntentRouter,
  EIP712('KSSessionIntentRouter', '1')
{
  bytes32 internal immutable ERC1155_DATA_TYPEHASH;
  bytes32 internal immutable ERC20_DATA_TYPEHASH;
  bytes32 internal immutable ERC721_DATA_TYPEHASH;
  bytes32 internal immutable TOKEN_DATA_TYPEHASH;
  bytes32 internal immutable INTENT_CORE_DATA_TYPEHASH;
  bytes32 internal immutable INTENT_DATA_TYPEHASH;
  bytes32 internal immutable ACTION_DATA_TYPEHASH;

  constructor() {
    (
      ERC1155_DATA_TYPEHASH,
      ERC20_DATA_TYPEHASH,
      ERC721_DATA_TYPEHASH,
      TOKEN_DATA_TYPEHASH,
      INTENT_CORE_DATA_TYPEHASH,
      INTENT_DATA_TYPEHASH,
      ACTION_DATA_TYPEHASH
    ) = _deriveTypehashes();
  }

  function _hashERC1155Data(ERC1155Data calldata data) internal view returns (bytes32) {
    return keccak256(
      abi.encode(
        ERC1155_DATA_TYPEHASH,
        data.token,
        keccak256(abi.encodePacked(data.tokenIds)),
        keccak256(abi.encodePacked(data.amounts)),
        keccak256(abi.encodePacked(data.minRefundAmounts))
      )
    );
  }

  function _hashERC20Data(ERC20Data calldata data) internal view returns (bytes32) {
    return keccak256(abi.encode(ERC20_DATA_TYPEHASH, data.token, data.amount, data.minRefundAmount));
  }

  function _hashERC721Data(ERC721Data calldata data) internal view returns (bytes32) {
    return keccak256(abi.encode(ERC721_DATA_TYPEHASH, data.token, data.tokenId));
  }

  function _hashTokenData(TokenData calldata data) internal view returns (bytes32) {
    bytes32[] memory erc1155DataHashes = new bytes32[](data.erc1155Data.length);
    for (uint256 i = 0; i < data.erc1155Data.length; i++) {
      erc1155DataHashes[i] = _hashERC1155Data(data.erc1155Data[i]);
    }

    bytes32[] memory erc20DataHashes = new bytes32[](data.erc20Data.length);
    for (uint256 i = 0; i < data.erc20Data.length; i++) {
      erc20DataHashes[i] = _hashERC20Data(data.erc20Data[i]);
    }

    bytes32[] memory erc721DataHashes = new bytes32[](data.erc721Data.length);
    for (uint256 i = 0; i < data.erc721Data.length; i++) {
      erc721DataHashes[i] = _hashERC721Data(data.erc721Data[i]);
    }

    return keccak256(
      abi.encode(
        TOKEN_DATA_TYPEHASH,
        keccak256(abi.encodePacked(erc1155DataHashes)),
        keccak256(abi.encodePacked(erc20DataHashes)),
        keccak256(abi.encodePacked(erc721DataHashes))
      )
    );
  }

  function _hashIntentCoreData(IntentCoreData calldata data) internal view returns (bytes32) {
    return keccak256(
      abi.encode(
        INTENT_CORE_DATA_TYPEHASH,
        data.mainWallet,
        data.sessionWallet,
        data.startTime,
        data.endTime,
        data.actionContract,
        data.actionSelector,
        data.validator,
        keccak256(data.validationData)
      )
    );
  }

  function _hashTypedIntentData(IntentData calldata data) internal view returns (bytes32) {
    return _hashTypedDataV4(
      keccak256(
        abi.encode(
          INTENT_DATA_TYPEHASH, _hashIntentCoreData(data.coreData), _hashTokenData(data.tokenData)
        )
      )
    );
  }

  function _hashTypedActionData(ActionData calldata data) internal view returns (bytes32) {
    return _hashTypedDataV4(
      keccak256(
        abi.encode(
          ACTION_DATA_TYPEHASH,
          _hashTokenData(data.tokenData),
          keccak256(data.actionCalldata),
          data.deadline
        )
      )
    );
  }

  function _deriveTypehashes()
    internal
    pure
    returns (
      bytes32 erc1155DataTypeHash,
      bytes32 erc20DataTypeHash,
      bytes32 erc721DataTypeHash,
      bytes32 tokenDataTypeHash,
      bytes32 intentCoreDataTypeHash,
      bytes32 intentDataTypeHash,
      bytes32 actionDataTypeHash
    )
  {
    bytes memory erc1155DataTypeString = abi.encodePacked(
      'ERC1155Data(address token,uint256[] tokenIds,uint256[] amounts,uint256[] minRefundAmounts)'
    );
    bytes memory erc20DataTypeString =
      abi.encodePacked('ERC20Data(address token,uint256 amount,uint256 minRefundAmount)');
    bytes memory erc721DataTypeString =
      abi.encodePacked('ERC721Data(address token,uint256 tokenId)');
    bytes memory tokenDataTypeString = abi.encodePacked(
      'TokenData(ERC1155Data[] erc1155Data,ERC20Data[] erc20Data,ERC721Data[] erc721Data)',
      erc1155DataTypeString,
      erc20DataTypeString,
      erc721DataTypeString
    );
    bytes memory intentCoreDataTypeString = abi.encodePacked(
      'IntentCoreData(address mainWallet,address sessionWallet,uint256 startTime,uint256 endTime,address actionContract,bytes4 actionSelector,address validator,bytes validationData)'
    );
    bytes memory intentDataTypeString = abi.encodePacked(
      'IntentData(IntentData intentData,TokenData tokenData)',
      intentCoreDataTypeString,
      tokenDataTypeString
    );
    bytes memory actionDataTypeString = abi.encodePacked(
      'ActionData(TokenData tokenData,bytes actionCalldata,uint256 deadline)', tokenDataTypeString
    );

    erc1155DataTypeHash = keccak256(erc1155DataTypeString);
    erc20DataTypeHash = keccak256(erc20DataTypeString);
    erc721DataTypeHash = keccak256(erc721DataTypeString);
    tokenDataTypeHash = keccak256(tokenDataTypeString);
    intentCoreDataTypeHash = keccak256(intentCoreDataTypeString);
    intentDataTypeHash = keccak256(intentDataTypeString);
    actionDataTypeHash = keccak256(actionDataTypeString);
  }
}
