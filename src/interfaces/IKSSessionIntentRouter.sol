// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IKSSessionIntentRouter {
  error NotMainWallet();

  error ExecuteTooEarly();

  error ExecuteTooLate();

  error IntentAlreadyExists();

  error IntentRevoked();

  error InvalidMainWalletSignature();

  error InvalidSessionWalletSignature();

  error InvalidOperatorSignature();

  error ERC1155InsufficientIntentAllowance(
    bytes32 intentHash, address token, uint256 tokenId, uint256 allowance, uint256 needed
  );

  error ERC20InsufficientIntentAllowance(
    bytes32 intentHash, address token, uint256 allowance, uint256 needed
  );

  error ERC721InsufficientIntentApproval(bytes32 intentHash, address token, uint256 tokenId);

  struct ERC20Data {
    address token;
    uint256 amount;
    uint256 minRefundAmount;
  }

  struct ERC721Data {
    address token;
    uint256 tokenId;
  }

  struct ERC1155Data {
    address token;
    uint256[] tokenIds;
    uint256[] amounts;
    uint256[] minRefundAmounts;
  }

  struct TokenData {
    ERC1155Data[] erc1155Data;
    ERC20Data[] erc20Data;
    ERC721Data[] erc721Data;
  }

  struct IntentCoreData {
    address mainWallet;
    address sessionWallet;
    uint256 startTime;
    uint256 endTime;
    address actionContract;
    bytes4 actionSelector;
    address validator;
    bytes validationData;
  }

  struct IntentData {
    IntentCoreData coreData;
    TokenData tokenData;
  }

  struct ActionData {
    TokenData tokenData;
    bytes actionCalldata;
    uint256 deadline;
  }

  function delegate(IntentData calldata intentData) external;

  function execute(
    bytes32 intentHash,
    bytes memory swSignature,
    address operator,
    bytes memory opSignature,
    ActionData calldata actionData
  ) external;

  function executeWithSignedIntent(
    IntentData calldata intentData,
    bytes memory mwSignature,
    bytes memory swSignature,
    address operator,
    bytes memory opSignature,
    ActionData calldata actionData
  ) external;
}
