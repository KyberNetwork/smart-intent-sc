/// @title IKSAllowanceHub
pragma solidity ^0.8.0;

/// @notice Interface for the KSAllowanceHub
interface IKSAllowanceHub {
  /**
   * @notice Parameters for collecting ERC20 tokens from `msg.sender`
   * @param token The address of the tokens to collect
   * @param targets The addresses to transfer the tokens to
   * @param amounts The amounts to transfer to each target
   * @param permitData The permit data for the tokens
   */
  struct ERC20Params {
    address token;
    address[] targets;
    uint256[] amounts;
    bytes permitData;
  }

  /**
   * @notice Parameters for collecting an ERC721 token from `msg.sender`
   * @param token The address of the token to collect
   * @param tokenId The token ID to collect
   * @param target The address to transfer the token to
   * @param permitData The permit data for the token
   */
  struct ERC721Params {
    address token;
    uint256 tokenId;
    address target;
    bytes permitData;
  }

  /**
   * @notice Parameters for calling a generic router
   * @param router The address of the router
   * @param value The value to send along with the call
   * @param data The data to call the generic router with
   */
  struct GenericCall {
    address router;
    uint256 value;
    bytes data;
  }

  /**
   * @notice Permits, transfers ERC20 and ERC721 tokens, executes generic calls
   * @param erc20Params The ERC20 tokens to transfer
   * @param erc721Params The ERC721 tokens to transfer
   * @param genericCalls The generic calls to execute
   * @return results The results of the generic calls
   * @return gasUsed The amount of gas used
   */
  function permitTransferAndExecute(
    ERC20Params[] calldata erc20Params,
    ERC721Params[] calldata erc721Params,
    GenericCall[] calldata genericCalls
  ) external payable returns (bytes[] memory results, uint256 gasUsed);
}
