// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IKSSwapRouterV3 {
  /// @notice Thrown when the msg.value is less than the required amount
  error NotEnoughMsgValue(uint256 required, uint256 provided);

  /// @notice Thrown when the output amount is less than the minimum amount
  error NotEnoughOutputAmount(uint256 minAmount, uint256 outputAmount);

  /// @notice Thrown when failed to call the executor
  error CallExecutorFailed();

  /// @notice Thrown when failed to call permit2
  error Permit2Failed();

  /// @notice Emitted when a swap is executed
  event Swap(
    address indexed sender,
    address indexed executor,
    address indexed recipient,
    address[] inputTokens,
    uint256[] inputAmounts,
    address[] outputTokens,
    uint256[] outputAmounts
  );

  /// @notice Emitted when the client data is set
  event ClientData(bytes clientData);

  /// @notice Emitted when the fee is collected
  event CollectFee(address token, uint256 totalAmount, uint256 feeAmount, address recipient);

  /// @notice Contains the additional data for an input token
  /// @param permitData The permit data
  /// @param feeRecipients The fee recipients
  /// @param fees The fees, either in bps or absolute value
  /// @param targets The targets to transfer the input token to
  /// @param amounts The amounts to transfer to the targets
  struct InputTokenData {
    // length = 5 * 32: IERC20Permit, use ERC20 `transferFrom`
    // length = 6 * 32: IDaiLikePermit, use ERC20 `transferFrom`
    // length = 0: use ERC20 `transferFrom`
    // otherwise: use Permit2 `transferFrom`
    bytes permitData;
    address[] feeRecipients;
    uint256[] fees;
    address[] targets;
    uint256[] amounts;
  }

  /// @notice Contains the additional data for an output token
  /// @param minAmount The minimum output amount
  /// @param feeRecipients The fee recipients
  /// @param fees The fees, either in bps or absolute value
  struct OutputTokenData {
    uint256 minAmount;
    address[] feeRecipients;
    uint256[] fees;
  }

  /// @notice Contains the parameters for a swap
  /// @param permit2Data The data to call permit2 with
  /// @param inputTokens The input tokens
  /// @param inputAmounts The input amounts
  /// @param inputData The additional data for the input tokens
  /// @param outputTokens The output tokens
  /// @param outputData The additional data for the output tokens
  /// @param executor The executor to call
  /// @param executorData The data to pass to the executor
  /// @param recipient The recipient of the output tokens
  /// @param clientData The client data
  struct SwapParams {
    bytes permit2Data;
    address[] inputTokens;
    uint256[] inputAmounts;
    InputTokenData[] inputData;
    address[] outputTokens;
    OutputTokenData[] outputData;
    address executor;
    bytes executorData;
    address recipient;
    bytes clientData;
  }

  /// @notice Entry point for swapping
  /// @param params The parameters for the swap
  function swap(SwapParams calldata params) external payable;

  /// @notice Returns the address of who called the swap function
  function msgSender() external view returns (address);
}
