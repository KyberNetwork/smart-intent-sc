// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './interfaces/IKSSessionIntentValidator.sol';

import 'ks-growth-utils-sc/KSRescueV2.sol';

import 'openzeppelin-contracts/interfaces/IERC1155Receiver.sol';
import 'openzeppelin-contracts/interfaces/IERC721Receiver.sol';

import 'openzeppelin-contracts/utils/Address.sol';
import 'openzeppelin-contracts/utils/ReentrancyGuard.sol';
import 'openzeppelin-contracts/utils/cryptography/EIP712.sol';
import 'openzeppelin-contracts/utils/cryptography/SignatureChecker.sol';

import 'forge-std/console.sol';

contract KSSessionIntentRouter is
  IKSSessionIntentRouter,
  KSRescueV2,
  EIP712('KSSessionIntentRouter', '1'),
  ReentrancyGuard,
  IERC1155Receiver,
  IERC721Receiver
{
  using SafeERC20 for IERC20;
  using Address for address;

  address internal constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

  bytes32 public immutable ERC1155_DATA_TYPEHASH;
  bytes32 public immutable ERC20_DATA_TYPEHASH;
  bytes32 public immutable ERC721_DATA_TYPEHASH;
  bytes32 public immutable TOKEN_DATA_TYPEHASH;
  bytes32 public immutable INTENT_CORE_DATA_TYPEHASH;
  bytes32 public immutable INTENT_DATA_TYPEHASH;
  bytes32 public immutable ACTION_DATA_TYPEHASH;

  mapping(bytes32 => mapping(address => uint256)) erc20Allowances;

  mapping(bytes32 => mapping(address => mapping(uint256 => uint256))) erc1155Allowances;

  mapping(bytes32 => IntentCoreData) public intents;

  constructor(
    address initialOwner,
    address[] memory initialOperators,
    address[] memory initialGuardians
  ) Ownable(initialOwner) {
    for (uint256 i = 0; i < initialOperators.length; i++) {
      operators[initialOperators[i]] = true;

      emit UpdateOperator(initialOperators[i], true);
    }
    for (uint256 i = 0; i < initialGuardians.length; i++) {
      guardians[initialGuardians[i]] = true;

      emit UpdateGuardian(initialGuardians[i], true);
    }

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

  function delegate(IntentData calldata intentData) public {
    require(intentData.coreData.mainWallet == _msgSender(), NotMainWallet());
    _delegate(intentData, 0);
  }

  function revoke(bytes32 intentHash) public {
    intents[intentHash].mainWallet = DEAD_ADDRESS;
  }

  function execute(
    bytes32 intentHash,
    bytes memory swSignature,
    address operator,
    bytes memory opSignature,
    ActionData calldata actionData
  ) public {
    _execute(intentHash, swSignature, operator, opSignature, actionData);
  }

  function executeWithSignedIntent(
    IntentData calldata intentData,
    bytes memory mwSignature,
    bytes memory swSignature,
    address operator,
    bytes memory opSignature,
    ActionData calldata actionData
  ) public {
    bytes32 intentHash = _hashTypedIntentData(intentData);
    require(
      SignatureChecker.isValidSignatureNow(intentData.coreData.mainWallet, intentHash, mwSignature),
      InvalidMainWalletSignature()
    );
    _delegate(intentData, intentHash);
    _execute(intentHash, swSignature, operator, opSignature, actionData);
  }

  function _delegate(IntentData calldata intentData, bytes32 intentHash) internal {
    if (intentHash == 0) intentHash = _hashTypedIntentData(intentData);
    console.log('length', intentData.tokenData.erc20Data.length);
    require(intents[intentHash].mainWallet == address(0), IntentAlreadyExists());
    intents[intentHash] = intentData.coreData;

    _approveTokens(intentHash, intentData.tokenData);
  }

  function _execute(
    bytes32 intentHash,
    bytes memory swSignature,
    address operator,
    bytes memory opSignature,
    ActionData calldata actionData
  ) internal nonReentrant {
    IntentCoreData storage intent = intents[intentHash];
    require(intent.mainWallet != DEAD_ADDRESS, IntentRevoked());
    require(block.timestamp >= intent.startTime, ExecuteTooEarly());
    require(block.timestamp <= intent.endTime, ExecuteTooLate());
    require(block.timestamp <= actionData.deadline, ExecuteTooLate());
    require(operators[operator], KyberSwapRole.KSRoleNotOperator(operator));

    bytes32 actionHash = _hashTypedActionData(actionData);
    if (_msgSender() != intent.sessionWallet) {
      require(
        SignatureChecker.isValidSignatureNow(intent.sessionWallet, actionHash, swSignature),
        InvalidSessionWalletSignature()
      );
    }
    if (_msgSender() != operator) {
      require(
        SignatureChecker.isValidSignatureNow(operator, actionHash, opSignature),
        InvalidOperatorSignature()
      );
    }

    _spendTokens(intentHash, intent.mainWallet, intent.actionContract, actionData.tokenData);
    bytes memory beforeExecutionData = IKSSessionIntentValidator(intent.validator)
      .validateBeforeExecution(intent, actionData.actionCalldata);
    bytes memory actionResult = intent.actionContract.functionCall(
      abi.encodePacked(intent.actionSelector, actionData.actionCalldata)
    );
    IKSSessionIntentValidator(intent.validator).validateAfterExecution(
      intent, beforeExecutionData, actionResult
    );
    _refundTokens(intent.mainWallet, actionData.tokenData);
  }

  function _approveTokens(bytes32 intentHash, TokenData calldata tokenData) internal {
    for (uint256 i = 0; i < tokenData.erc1155Data.length; i++) {
      ERC1155Data calldata erc1155Data = tokenData.erc1155Data[i];
      for (uint256 j = 0; j < erc1155Data.tokenIds.length; j++) {
        erc1155Allowances[intentHash][erc1155Data.token][erc1155Data.tokenIds[j]] =
          erc1155Data.amounts[j];
      }
    }
    for (uint256 i = 0; i < tokenData.erc20Data.length; i++) {
      ERC20Data calldata erc20Data = tokenData.erc20Data[i];
      erc20Allowances[intentHash][erc20Data.token] = erc20Data.amount;
    }
  }

  function _spendTokens(
    bytes32 intentHash,
    address mainWallet,
    address actionContract,
    TokenData calldata tokenData
  ) internal {
    for (uint256 i = 0; i < tokenData.erc1155Data.length; i++) {
      ERC1155Data calldata erc1155Data = tokenData.erc1155Data[i];
      IERC1155 token = IERC1155(erc1155Data.token);
      for (uint256 j = 0; j < erc1155Data.tokenIds.length; j++) {
        erc1155Allowances[intentHash][erc1155Data.token][erc1155Data.tokenIds[j]] -=
          erc1155Data.amounts[j];
      }
      token.safeBatchTransferFrom(
        mainWallet, address(this), erc1155Data.tokenIds, erc1155Data.amounts, ''
      );
      token.setApprovalForAll(actionContract, true);
    }
    for (uint256 i = 0; i < tokenData.erc20Data.length; i++) {
      ERC20Data calldata erc20Data = tokenData.erc20Data[i];
      erc20Allowances[intentHash][erc20Data.token] -= erc20Data.amount;
      IERC20(erc20Data.token).safeTransferFrom(mainWallet, address(this), erc20Data.amount);
      _safeApproveInf(erc20Data.token, actionContract);
    }
    for (uint256 i = 0; i < tokenData.erc721Data.length; i++) {
      ERC721Data calldata erc721Data = tokenData.erc721Data[i];
      IERC721 token = IERC721(erc721Data.token);
      token.safeTransferFrom(mainWallet, address(this), erc721Data.tokenId);
      token.approve(actionContract, erc721Data.tokenId);
    }
  }

  function _refundTokens(address mainWallet, TokenData calldata tokenData) internal {
    for (uint256 i = 0; i < tokenData.erc1155Data.length; i++) {
      ERC1155Data calldata erc1155Data = tokenData.erc1155Data[i];
      IERC1155 token = IERC1155(erc1155Data.token);
      address[] memory owners = new address[](erc1155Data.tokenIds.length);
      for (uint256 j = 0; j < erc1155Data.tokenIds.length; j++) {
        owners[j] = address(this);
      }
      uint256[] memory balances = token.balanceOfBatch(owners, erc1155Data.tokenIds);
      for (uint256 j = 0; j < erc1155Data.tokenIds.length; j++) {
        if (balances[j] > 0) {
          balances[j]--;
        }
        if (balances[j] < erc1155Data.minRefundAmounts[j]) {
          balances[j] = 0;
        }
      }
      token.safeBatchTransferFrom(address(this), mainWallet, erc1155Data.tokenIds, balances, '');
    }
    for (uint256 i = 0; i < tokenData.erc20Data.length; i++) {
      ERC20Data calldata erc20Data = tokenData.erc20Data[i];
      IERC20 token = IERC20(erc20Data.token);
      uint256 balance = token.balanceOf(address(this));
      if (balance >= erc20Data.minRefundAmount + 1) {
        token.safeTransfer(mainWallet, balance - 1);
      }
    }
    for (uint256 i = 0; i < tokenData.erc721Data.length; i++) {
      ERC721Data calldata erc721Data = tokenData.erc721Data[i];
      IERC721 token = IERC721(erc721Data.token);
      try token.safeTransferFrom(address(this), mainWallet, erc721Data.tokenId) {} catch {}
    }
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

  function onERC721Received(address, address, uint256, bytes calldata)
    external
    pure
    returns (bytes4)
  {
    return IERC721Receiver.onERC721Received.selector;
  }

  function onERC1155Received(address, address, uint256, uint256, bytes calldata)
    external
    pure
    returns (bytes4)
  {
    return IERC1155Receiver.onERC1155Received.selector;
  }

  function onERC1155BatchReceived(
    address,
    address,
    uint256[] calldata,
    uint256[] calldata,
    bytes calldata
  ) external pure returns (bytes4) {
    return IERC1155Receiver.onERC1155BatchReceived.selector;
  }

  function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
    return interfaceId == type(IERC1155Receiver).interfaceId
      || interfaceId == type(IERC721Receiver).interfaceId;
  }

  function _safeApproveInf(address token, address spender) internal {
    if (IERC20(token).allowance(address(this), spender) == 0) {
      IERC20(token).forceApprove(spender, type(uint256).max);
    }
  }
}
