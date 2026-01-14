// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IKSSwapRouterV3 {
  /// @notice Contains the additional data for an input token
  /// @param permitData The permit data
  /// @param feeRecipients The fee recipients
  /// @param fees The fees, either in bps or absolute value
  /// @param targets The targets to transfer the input token to
  /// @param amounts The amounts to transfer to the targets
  struct InputTokenData {
    // Permit method selection:
    // length = 5 * 32: use ERC20 `permit`
    // length = 6 * 32: use DAI `permit`
    // Transfer method selection:
    // length == 0: use Permit2 `transferFrom`
    // length != 0: use ERC20 `transferFrom`
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
  /// @param inputTokens The input tokens
  /// @param inputAmounts The input amounts (only used for fee calculation)
  /// @param inputData The additional data for the input tokens
  /// @param outputTokens The output tokens
  /// @param outputData The additional data for the output tokens
  /// @param permit2Data The data to call permit2 with
  /// @param executor The executor to call
  /// @param executorData The data to pass to the executor
  /// @param recipient The recipient of the output tokens
  /// @param deadline The deadline for the swap
  /// @param clientData The client data
  struct SwapParams {
    address[] inputTokens;
    uint256[] inputAmounts;
    InputTokenData[] inputData;
    address[] outputTokens;
    OutputTokenData[] outputData;
    bytes permit2Data;
    address executor;
    bytes executorData;
    address recipient;
    uint256 deadline;
    bytes clientData;
  }

  /// @notice Entry point for swapping
  /// @param params The parameters for the swap
  function swap(SwapParams calldata params)
    external
    payable
    returns (uint256[] memory outputAmounts, uint256 gasUsed);

  /// @notice Returns the address of who called the swap function
  function msgSender() external view returns (address);
}
